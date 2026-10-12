# frozen_string_literal: true

module DrTalon
  module Engine
    # Reads identifying details out of an unpacked DragonRuby distribution.
    #
    # - version: the first "* X.Y" heading in +CHANGELOG-CURR.txt+
    #   (+VERSION.txt+ only has the build date and git sha)
    # - platform: from the root directory name, +dragonruby-<platform>+
    # - tier: from names such as the zip's, +dragonruby-pro-linux-amd64.zip+;
    #   the engine files themselves don't say
    class Inspector
      CHANGELOG = "CHANGELOG-CURR.txt"
      VERSION_FILE = "VERSION.txt"
      BINARIES = %w[dragonruby dragonruby.exe].freeze

      # Finds the engine root at +dir+ or directly inside it, which covers both
      # an extracted zip (+dragonruby-pro-linux-amd64/dragonruby-linux-amd64/+)
      # and the engine directory itself.
      #
      # @param dir [String]
      # @return [String]
      # @raise [InvalidEngine] if there isn't exactly one engine root
      def self.find_root(dir)
        return dir if engine_root?(dir)

        candidates = Dir.children(dir).map { |child| File.join(dir, child) }.select { |path| engine_root?(path) }
        return candidates.first if candidates.one?

        if candidates.empty?
          raise InvalidEngine, "#{dir} doesn't look like a DragonRuby engine " \
            "(no directory with #{CHANGELOG} and a dragonruby binary)."
        end

        raise InvalidEngine, "#{dir} contains more than one DragonRuby engine: " \
          "#{candidates.map { |path| File.basename(path) }.join(", ")}"
      end

      # @param dir [String]
      # @return [Boolean]
      def self.engine_root?(dir)
        File.directory?(dir) &&
          File.file?(File.join(dir, CHANGELOG)) &&
          BINARIES.any? { |binary| File.file?(File.join(dir, binary)) }
      end

      # @param root [String] the engine root, see {.find_root}
      # @param hints [Array<String>] names to look for a tier in, such as the
      #   zip's basename
      # @param tier [String, nil] overrides tier detection
      # @param platform [String, nil] overrides platform detection
      def initialize(root, hints: [], tier: nil, platform: nil)
        @root = root
        @hints = hints
        @tier = tier
        @platform = platform
      end

      # @return [Hash{Symbol => String, nil}] +version+, +tier+, +platform+,
      #   +build_date+ and +git_sha+
      # @raise [InvalidEngine] if a required detail can't be determined
      def details
        {version: version, tier: tier, platform: platform, **build_info}
      end

      private

      def version
        File.foreach(File.join(@root, CHANGELOG)) do |line|
          match = /\A\* (\d+(?:\.\d+)+)\s*\z/.match(line)
          return match[1] if match
        end

        raise InvalidEngine, "Can't find a version heading (e.g. \"* 7.23\") in #{CHANGELOG}."
      end

      def tier
        return validate_tier(@tier) if @tier

        names = [*@hints, File.basename(@root)]
        found = names.filter_map { |name| /(?:\A|[-_])(#{TIERS.join("|")})(?=[-_.]|\z)/.match(name)&.[](1) }.uniq
        return found.first if found.one?

        raise InvalidEngine, "Can't tell the license tier from #{names.uniq.join(", ")}. " \
          "Pass --tier #{TIERS.join("|")}."
      end

      def platform
        return @platform if @platform

        match = /\Adragonruby-([a-z0-9-]+)\z/.match(File.basename(@root))
        return match[1] if match

        raise InvalidEngine, "Can't tell the platform from #{File.basename(@root)}. " \
          "Pass --platform, e.g. --platform #{Engine.host_platform}."
      end

      def validate_tier(tier)
        return tier if TIERS.include?(tier)

        raise InvalidEngine, "Unknown tier \"#{tier}\". Expected one of #{TIERS.join(", ")}."
      end

      def build_info
        path = File.join(@root, VERSION_FILE)
        lines = File.file?(path) ? File.readlines(path, chomp: true) : []
        fields = lines.filter_map { |line| line.split(": ", 2) if line.include?(": ") }.to_h

        {build_date: fields["date"], git_sha: fields["git"]}
      end
    end
  end
end
