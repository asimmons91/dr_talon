# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module DrTalon
  module Engine
    # The global cache of unpacked engines, one directory per {Installation#id}.
    #
    # DragonRuby only offers its latest release for download, so this cache is
    # also the only archive of older versions.
    class Store
      # @return [String]
      attr_reader :root

      # @param root [String] usually {Paths#engines_dir}
      # @param host_platform [String] preferred when a spec omits the platform
      def initialize(root, host_platform: Engine.host_platform)
        @root = root
        @host_platform = host_platform
      end

      # @return [Array<Installation>] newest version first, then the most
      #   capable tier (see {TIERS})
      def installations
        return [] unless File.directory?(root)

        Dir.children(root)
          .reject { |name| name.start_with?(".") }
          .map { |name| File.join(root, name) }
          .select { |path| File.file?(File.join(path, Installation::METADATA_FILE)) }
          .map { |path| Installation.load(path) }
          .sort { |a, b| sort_key(b) <=> sort_key(a) }
      end

      # @param id [String] a full {Installation#id}
      # @return [Installation, nil]
      def get(id)
        path = path_for(id)
        Installation.load(path) if File.file?(File.join(path, Installation::METADATA_FILE))
      end

      # Resolves a possibly partial spec to one installation. When the spec
      # omits the platform, engines for the host platform win.
      #
      # @param spec [String, Spec]
      # @return [Installation]
      # @raise [NotFound, Ambiguous]
      def find(spec)
        spec = Spec.parse(spec) unless spec.is_a?(Spec)
        matches = installations.select { |installation| spec.match?(installation) }
        raise NotFound, "No cached engine matches #{spec}. Run `talon engine list` to see what's installed." if matches.empty?

        if matches.size > 1 && spec.platform.nil?
          native = matches.select { |installation| installation.platform == @host_platform }
          matches = native unless native.empty?
        end
        return matches.first if matches.one?

        raise Ambiguous, "#{spec} matches more than one engine: #{matches.map(&:id).join(", ")}. Use a full id."
      end

      # Resolves +spec+ to an engine built for this machine, since a project
      # can only run its host's build.
      #
      # @param spec [Spec]
      # @param default_tier [String, nil] used when +spec+ omits the tier
      # @return [Installation]
      # @raise [Error] if +spec+ names another platform
      # @raise [NotFound, Ambiguous]
      def find_native(spec, default_tier: nil)
        if spec.platform && spec.platform != @host_platform
          raise Error, "This machine runs #{@host_platform} engines; #{spec} is for #{spec.platform}."
        end

        find(Spec.new(version: spec.version, tier: spec.tier || default_tier, platform: @host_platform))
      end

      # @return [Installation, nil] the newest engine for this machine
      def latest_native
        installations.find { |installation| installation.platform == @host_platform }
      end

      # @param id [String]
      # @return [String]
      def path_for(id)
        File.join(root, id)
      end

      # Larger sorts first: newer versions, then more capable tiers.
      def sort_key(installation)
        [installation.gem_version, -(TIERS.index(installation.tier) || TIERS.size), installation.platform]
      end
      private :sort_key

      # Deletes an installation from the cache.
      #
      # @param installation [Installation]
      # @return [void]
      def remove(installation)
        FileUtils.rm_rf(installation.path)
      end

      # Yields an empty directory inside the store, on the same filesystem, so
      # a finished import can be moved into place with a rename. The directory
      # is removed afterwards.
      #
      # @yieldparam dir [String]
      # @return [Object] the block's result
      def stage
        FileUtils.mkdir_p(root)
        dir = Dir.mktmpdir(".staging-", root)
        yield dir
      ensure
        FileUtils.rm_rf(dir) if dir
      end
    end
  end
end
