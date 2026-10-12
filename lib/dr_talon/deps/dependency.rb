# frozen_string_literal: true

require "digest"
require "tmpdir"
require "uri"

module DrTalon
  module Deps
    # Where sources fetch from; tests swap in local fakes.
    Context = Data.define(:http, :git, :github_url, :codeload_url) do
      def self.default
        new(http: DrTalon::HTTP.new, git: Git.new, github_url: "https://github.com", codeload_url: "https://codeload.github.com")
      end
    end

    # One entry in +dependencies.rb+: where it comes from and where it's
    # vendored inside the game directory.
    class Dependency
      VENDOR = "vendor"

      # @return [String] short name, used by `talon add/remove/update`
      attr_reader :name
      # @return [String] game-relative path the files are written to
      attr_reader :destination
      # @return [String, nil] requested branch, tag or commit
      attr_reader :ref
      # @return [Integer, nil] line in dependencies.rb that declared it
      attr_reader :line

      # @param name [String, nil] defaults to {#default_name}
      # @param destination [String, nil] defaults to vendor/NAME
      def initialize(name: nil, destination: nil, ref: nil, line: nil)
        @ref = ref&.to_s
        @line = line
        @destination = destination&.to_s || "#{VENDOR}/#{name || default_name}"
        @name = (name || (destination ? File.basename(@destination) : default_name)).to_s
        validate_destination!
      end

      # @return [String] the lock key, in Foodchain's format where one exists
      def key
        raise NotImplementedError
      end

      # @return [Boolean] whether {#resolve} pins a version (path deps don't)
      def lockable?
        true
      end

      # The commit (or content digest) to install for the current {#ref}.
      #
      # @param context [Context]
      # @return [String, nil]
      def resolve(context)
        raise NotImplementedError
      end

      # Writes the dependency's files for +commit+ to +target+.
      #
      # @param context [Context]
      # @param commit [String, nil]
      # @param target [String] absolute path; doesn't exist yet
      # @return [void]
      def fetch(context, commit, target)
        raise NotImplementedError
      end

      # @return [String] e.g. "github:asimmons91/talon (lib)"
      def to_s
        key
      end

      private

      def default_name
        raise NotImplementedError
      end

      def validate_destination!
        parts = @destination.split("/")
        return if parts.first == VENDOR && parts.size > 1 && !parts.include?("..") && !parts.include?("") &&
          !@destination.start_with?("/")

        raise ManifestError, "Dependency destination #{@destination.inspect} must be inside #{VENDOR}/, " \
          "e.g. #{VENDOR}/#{File.basename(@destination)}. talon replaces it on install."
      end

      def subpath_name(subpath, fallback)
        base = File.basename(subpath.to_s)
        (subpath.to_s.empty? || !base.include?(".")) ? fallback : base
      end
    end

    # A path inside a GitHub repository, downloaded as a tarball of the
    # resolved commit.
    class GitHubDependency < Dependency
      attr_reader :owner, :repo, :subpath

      def initialize(owner, repo, subpath: nil, **options)
        @owner = owner.to_s
        @repo = repo.to_s
        @subpath = subpath.to_s.delete_prefix("/").delete_suffix("/")
        super(**options)
      end

      def key
        ["github:#{owner}/#{repo}", (subpath unless subpath.empty?)].compact.join("/")
      end

      def resolve(context)
        context.git.resolve("#{context.github_url}/#{owner}/#{repo}.git", ref)
      end

      def fetch(context, commit, target)
        data = context.http.get("#{context.codeload_url}/#{owner}/#{repo}/tar.gz/#{commit}")
        Dir.mktmpdir("talon-github") do |dir|
          Tree.untar(data, dir)
          Tree.copy_subpath(dir, subpath, target)
        end
      end

      private

      def default_name
        subpath_name(subpath, repo)
      end
    end

    # A path inside any git repository, fetched with the git CLI.
    class GitDependency < Dependency
      attr_reader :url, :subpath

      def initialize(url, subpath: nil, **options)
        @url = url.to_s
        @subpath = subpath.to_s.delete_prefix("/").delete_suffix("/")
        super(**options)
      end

      def key
        subpath.empty? ? "git:#{url}" : "git:#{url}?path=#{subpath}"
      end

      def resolve(context)
        context.git.resolve(url, ref)
      end

      def fetch(context, commit, target)
        Dir.mktmpdir("talon-git") do |dir|
          checkout = File.join(dir, "repo")
          context.git.checkout(url, commit, checkout)
          Tree.copy_subpath(checkout, subpath, target)
        end
      end

      private

      def default_name
        subpath_name(subpath, File.basename(url.chomp("/"), ".git"))
      end
    end

    # A single file downloaded from a URL, pinned by its SHA-256.
    class URLDependency < Dependency
      attr_reader :url

      def initialize(url, **options)
        @url = url.to_s
        super(**options)
      end

      def key
        url
      end

      def resolve(context)
        @body = context.http.get(url)
        "sha256:#{Digest::SHA256.hexdigest(@body)}"
      end

      def fetch(context, commit, target)
        body = @body || context.http.get(url)
        digest = "sha256:#{Digest::SHA256.hexdigest(body)}"
        if commit && digest != commit
          raise FetchError, "#{url} has changed since it was locked. Run `talon update #{name}` to accept the new version."
        end

        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite(target, body)
      end

      private

      def default_name
        File.basename(URI(url).path)
      rescue URI::InvalidURIError
        raise ManifestError, "Invalid URL: #{url}"
      end
    end

    # A local file or directory, copied on every install. For developing a
    # library alongside a game.
    class PathDependency < Dependency
      attr_reader :path

      # @param path [String] as written in dependencies.rb
      # @param base [String] what a relative +path+ is relative to
      def initialize(path, base:, **options)
        @path = path.to_s
        @absolute = File.expand_path(@path, base)
        super(**options)
      end

      def key
        "path:#{path}"
      end

      def lockable?
        false
      end

      def resolve(_context)
        nil
      end

      def fetch(_context, _commit, target)
        raise FetchError, "#{@absolute} doesn't exist." unless File.exist?(@absolute)

        Tree.copy_subpath(@absolute, "", target)
      end

      private

      def default_name
        File.basename(@path.chomp("/"))
      end
    end
  end
end
