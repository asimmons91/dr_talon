# frozen_string_literal: true

module DrTalon
  module Engine
    Spec = Data.define(:version, :tier, :platform)

    # A possibly partial engine identifier given on the command line:
    # "7.23", "7.23-pro" or "7.23-pro-linux-amd64".
    class Spec
      PATTERN = /\A(?<version>\d+(?:\.\d+)+)(?:-(?<tier>#{TIERS.join("|")})(?:-(?<platform>[a-z0-9-]+))?)?\z/

      # @param string [String]
      # @return [Spec]
      # @raise [Error] if +string+ isn't a valid spec
      def self.parse(string)
        match = PATTERN.match(string.to_s.strip)
        unless match
          raise Error, "Invalid engine \"#{string}\". Expected VERSION[-TIER[-PLATFORM]], e.g. 7.23 or 7.23-pro."
        end

        new(version: match[:version], tier: match[:tier], platform: match[:platform])
      end

      # @param installation [Installation]
      # @return [Boolean] whether every part this spec names matches
      def match?(installation)
        installation.version == version &&
          (tier.nil? || installation.tier == tier) &&
          (platform.nil? || installation.platform == platform)
      end

      # @return [String]
      def to_s
        [version, tier, platform].compact.join("-")
      end
    end
  end
end
