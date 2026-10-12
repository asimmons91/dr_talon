# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

module DrTalon
  module Engine
    # Downloads the latest Pro or Indie engine from dragonruby.org.
    #
    # The subscription API answers with the zip's download URL (as its body or
    # a redirect), or with the zip itself; all three are handled.
    class Fetcher
      API = "https://dragonruby.org/api/download_%<tier>s_subscription_%<os>s"
      TIERS = %w[pro indie].freeze

      # dragonruby.org's name for each platform talon knows.
      OS_NAMES = {"linux-amd64" => "linux", "macos" => "mac", "windows-amd64" => "windows"}.freeze

      ZIP_MAGIC = "PK\x03\x04".b

      # @param http [HTTP]
      # @param downloads_dir [String] where the zip is saved
      # @param platform [String]
      # @param api [String] format string for the API URL (+tier+, +os+)
      def initialize(http: HTTP.new, downloads_dir: Paths.new.downloads_dir, platform: Engine.host_platform, api: API)
        @http = http
        @downloads_dir = downloads_dir
        @platform = platform
        @api = api
      end

      # @param tier [String] "pro" or "indie"
      # @return [String] the API URL for this machine
      # @raise [Error] for other tiers or platforms
      def api_url(tier)
        raise Error, "dragonruby.org downloads are for #{TIERS.join(" and ")}; use butler for #{tier}." unless TIERS.include?(tier)

        os = OS_NAMES.fetch(@platform) do
          raise Error, "dragonruby.org has no #{tier} download for #{@platform}. Download it by hand and run `talon engine import`."
        end
        format(@api, tier: tier, os: os)
      end

      # Checks a login without downloading the engine.
      #
      # @param credentials [Credentials]
      # @param tier [String]
      # @return [void]
      # @raise [HTTP::Unauthorized, HTTP::Error]
      def verify(credentials, tier)
        Dir.mktmpdir("talon-login") do |dir|
          probe(api_url(tier), credentials, File.join(dir, "response"))
        end
      end

      # @param credentials [Credentials]
      # @param tier [String]
      # @yieldparam received [Integer]
      # @yieldparam total [Integer, nil]
      # @return [String] path to the downloaded zip
      # @raise [HTTP::Unauthorized, HTTP::Error, Error]
      def fetch(credentials, tier, &progress)
        FileUtils.mkdir_p(@downloads_dir)
        path = File.join(@downloads_dir, "dragonruby-#{tier}-#{@platform}.zip")

        response = @http.download(api_url(tier), path, auth: credentials.to_auth, &progress)
        return path if zip?(response)

        url = File.read(response, 4096).to_s.strip
        unless url.match?(%r{\Ahttps?://\S+\z})
          raise Error, "dragonruby.org answered with something other than a download link or zip."
        end

        @http.download(url, path, &progress)
        raise Error, "The download from #{URI(url).host} isn't a zip." unless zip?(path)

        path
      rescue Exception # rubocop:disable Lint/RescueException -- also clean up on Ctrl-C
        FileUtils.rm_f(path) if path
        raise
      end

      private

      # Fetches just enough of the API response to know the login works,
      # stopping early in case it's the zip itself.
      def probe(url, credentials, path)
        catch(:enough) do
          @http.download(url, path, auth: credentials.to_auth) do |received, _total|
            throw :enough if received > 64 * 1024
          end
        end
      end

      def zip?(path)
        File.binread(path, 4) == ZIP_MAGIC
      end
    end

    # Downloads the latest Standard engine from itch.io with butler.
    class ButlerFetcher
      GAME = "dragonruby/dragonruby-gtk"

      # @param platform [String] also the itch.io channel name
      # @param butler [String] the butler executable
      def initialize(platform: Engine.host_platform, butler: "butler")
        @platform = platform
        @butler = butler
      end

      # @param dir [String] empty directory to download into
      # @return [String] +dir+, ready for {Importer#import}
      # @raise [Error] if butler is missing or the fetch fails
      def fetch(dir)
        _out, err, status = Open3.capture3(@butler, "fetch", "#{GAME}:#{@platform}", dir)
        return dir if status.success?

        raise Error, "butler fetch failed: #{err.strip}. If you haven't yet, run `butler login`."
      rescue Errno::ENOENT
        raise Error, "Standard engines download with itch.io's butler, which isn't installed. " \
          "See https://itch.io/docs/butler/installing.html, then run `butler login`."
      end
    end
  end
end
