# frozen_string_literal: true

require "cgi/escape"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

module DrTalon
  module Engine
    # Download the latest engine of a tier for this machine. Each fetcher's
    # #fetch returns a zip or directory to hand to {Importer#import}; the
    # caller deletes it afterwards.
    module Fetchers
      ZIP_MAGIC = "PK\x03\x04".b

      # @param tier [String] one of {TIERS}
      # @param options [Hash] passed to the fetcher (http:, downloads_dir:, platform:, ...)
      # @return [DragonRubyAPI, ItchJam, Butler]
      def self.for(tier, **options)
        case tier
        when "pro", "indie" then DragonRubyAPI.new(tier, **options)
        when "jam" then ItchJam.new(**options.except(:butler))
        when "standard" then Butler.new(**options.slice(:platform, :downloads_dir, :butler))
        else raise Error, "Unknown tier \"#{tier}\". Expected one of #{TIERS.join(", ")}."
        end
      end

      # @param path [String]
      # @return [Boolean]
      def self.zip?(path)
        File.file?(path) && File.binread(path, 4) == ZIP_MAGIC
      end

      # Downloads +url+ to +path+, deleting a partial or non-zip result.
      #
      # @return [String] +path+
      # @raise [Error]
      def self.download_zip(http, url, path, auth: nil, &progress)
        FileUtils.mkdir_p(File.dirname(path))
        http.download(url, path, auth: auth, &progress)
        raise Error, "The download from #{URI(url).host} isn't a zip." unless zip?(path)

        path
      rescue Exception # rubocop:disable Lint/RescueException -- also clean up on Ctrl-C
        FileUtils.rm_f(path)
        raise
      end

      # Pro and Indie, from dragonruby.org's subscription API with the
      # account's login. The API answers with the zip's URL (as its body or a
      # redirect) or with the zip itself; all three are handled.
      class DragonRubyAPI
        API = "https://dragonruby.org/api/download_%<tier>s_subscription_%<os>s"

        # dragonruby.org's name for each platform it has downloads for.
        OS_NAMES = {"linux-amd64" => "linux", "macos" => "mac", "windows-amd64" => "windows"}.freeze

        # @return [String]
        attr_reader :tier

        # @param tier [String] "pro" or "indie"
        # @param http [HTTP]
        # @param downloads_dir [String] where the zip is saved
        # @param platform [String]
        # @param api [String] format string for the API URL (+tier+, +os+)
        def initialize(tier, http: HTTP.new, downloads_dir: Paths.new.downloads_dir, platform: Engine.host_platform, api: API)
          @tier = tier
          @http = http
          @downloads_dir = downloads_dir
          @platform = platform
          @api = api
        end

        # @return [Boolean]
        def credentials?
          true
        end

        # @return [String] the API URL for this machine
        # @raise [Error] if dragonruby.org has no download for the platform
        def api_url
          os = OS_NAMES.fetch(@platform) do
            raise Error, "dragonruby.org has no #{tier} download for #{@platform}. " \
              "Download it by hand and run `talon engine import`."
          end
          format(@api, tier: tier, os: os)
        end

        # Checks a login without downloading the engine.
        #
        # @param credentials [Credentials]
        # @return [void]
        # @raise [HTTP::Unauthorized, HTTP::Error]
        def verify(credentials)
          Dir.mktmpdir("talon-login") do |dir|
            # Stop early in case the answer is the zip itself.
            catch(:enough) do
              @http.download(api_url, File.join(dir, "response"), auth: credentials.to_auth) do |received, _total|
                throw :enough if received > 64 * 1024
              end
            end
          end
        end

        # @param credentials [Credentials]
        # @return [String] path to the downloaded zip
        # @raise [HTTP::Unauthorized, HTTP::Error, Error]
        def fetch(credentials:, &progress)
          raise Error, "A dragonruby.org login is needed for #{tier}." unless credentials

          path = File.join(@downloads_dir, "dragonruby-#{tier}-#{@platform}.zip")
          FileUtils.mkdir_p(@downloads_dir)
          @http.download(api_url, path, auth: credentials.to_auth, &progress)
          return path if Fetchers.zip?(path)

          url = File.read(path, 4096).to_s.strip
          FileUtils.rm_f(path)
          unless url.match?(%r{\Ahttps?://\S+\z})
            raise Error, "dragonruby.org answered with something other than a download link or zip."
          end

          Fetchers.download_zip(@http, url, path, &progress)
        rescue Exception # rubocop:disable Lint/RescueException -- also clean up on Ctrl-C
          FileUtils.rm_f(path) if path
          raise
        end
      end

      # Jam, DragonRuby's free license, from the demo uploads on its itch.io
      # page. No account is needed: the page's download button posts to
      # itch.io for a short-lived link, and so does this.
      class ItchJam
        PAGE = "https://dragonruby.itch.io/dragonruby-gtk"

        # The itch.io upload names for each platform.
        UPLOADS = {
          "linux-amd64" => "x64 Linux Jam License",
          "linux-arm64" => "arm64 Linux Jam License",
          "macos" => "macOS Jam License",
          "windows-amd64" => "Windows Jam License"
        }.freeze

        # @param http [HTTP]
        # @param downloads_dir [String]
        # @param platform [String]
        # @param page [String] the itch.io game page
        def initialize(http: HTTP.new, downloads_dir: Paths.new.downloads_dir, platform: Engine.host_platform, page: PAGE)
          @http = http
          @downloads_dir = downloads_dir
          @platform = platform
          @page = page
        end

        # @return [String]
        def tier
          "jam"
        end

        # @return [Boolean]
        def credentials?
          false
        end

        # @return [String] path to the downloaded zip
        # @raise [HTTP::Error, Error]
        def fetch(credentials: nil, &progress)
          name = UPLOADS.fetch(@platform) { raise Error, "There's no Jam license download for #{@platform}." }
          html = @http.get(@page)
          token = html.scan(/<(?:meta|input)\b[^>]*>/).map { |tag| attributes(tag) }
            .find { |attrs| attrs["name"] == "csrf_token" }&.dig("value")
          id = demo_uploads(html)[name]
          unless token && id
            raise Error, "Couldn't find the \"#{name}\" download on #{@page}; itch.io's page may have changed. " \
              "Download it by hand and run `talon engine import`."
          end

          answer = JSON.parse(@http.post_form("#{@page}/file/#{id}?source=view_game&as_props=1&after_download_lightbox=true",
            "csrf_token" => token))
          url = answer["url"] if answer.is_a?(Hash)
          raise Error, "itch.io didn't return a download link for \"#{name}\"." unless url.is_a?(String)

          Fetchers.download_zip(@http, url, File.join(@downloads_dir, "dragonruby-gtk-#{@platform}-jam.zip"), &progress)
        rescue JSON::ParserError
          raise Error, "itch.io answered the download request with something other than JSON."
        end

        private

        # @return [Hash{String => String}] upload name => upload id, from the
        #   page's "Download demo" section. itch.io doesn't keep attribute
        #   order stable between requests, so tags are parsed attribute by
        #   attribute.
        def demo_uploads(html)
          section = html[/class="[^"]*\bfor_demo\b.*?(?=<section\b|\z)/m].to_s
          section.split(/(?=<div\b[^>]*\bclass="upload")/).filter_map do |upload|
            id = upload.scan(/<a\b[^>]*>/).filter_map { |tag| attributes(tag)["data-upload_id"] }.first
            title = upload.scan(/<strong\b[^>]*>/).filter_map { |tag| attributes(tag)["title"] }.first
            [CGI.unescapeHTML(title), id] if id && title
          end.to_h
        end

        # @return [Hash{String => String}]
        def attributes(tag)
          tag.scan(/([\w-]+)="([^"]*)"/).to_h
        end
      end

      # Standard, from itch.io with butler (after `butler login`).
      class Butler
        GAME = "dragonruby/dragonruby-gtk"

        # @param platform [String] also the itch.io channel name
        # @param downloads_dir [String] where butler's directory is created
        # @param butler [String] the butler executable
        def initialize(platform: Engine.host_platform, downloads_dir: Paths.new.downloads_dir, butler: "butler")
          @platform = platform
          @downloads_dir = downloads_dir
          @butler = butler
        end

        # @return [String]
        def tier
          "standard"
        end

        # @return [Boolean]
        def credentials?
          false
        end

        # @return [String] a directory containing the engine
        # @raise [Error] if butler is missing or the fetch fails
        def fetch(credentials: nil)
          FileUtils.mkdir_p(@downloads_dir)
          dir = Dir.mktmpdir("butler-", @downloads_dir)
          _out, err, status = Open3.capture3(@butler, "fetch", "#{GAME}:#{@platform}", dir)
          return dir if status.success?

          FileUtils.rm_rf(dir)
          raise Error, "butler fetch failed: #{err.strip}. If you haven't yet, run `butler login`."
        rescue Errno::ENOENT
          FileUtils.rm_rf(dir) if dir
          raise Error, "Standard engines download with itch.io's butler, which isn't installed. " \
            "See https://itch.io/docs/butler/installing.html, then run `butler login`. " \
            "The free Jam license needs neither: `talon engine fetch --tier jam`."
        end
      end
    end
  end
end
