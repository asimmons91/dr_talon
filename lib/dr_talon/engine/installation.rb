# frozen_string_literal: true

require "time"
require "yaml"

module DrTalon
  module Engine
    Installation = Data.define(
      :version, :tier, :platform, :path, :build_date, :git_sha, :sha256, :source, :imported_at
    )

    # An engine unpacked in the {Store}. Its details are recorded in a
    # +.talon-engine.yml+ file at the engine root.
    #
    # @!attribute [r] version
    #   @return [String] release number from +CHANGELOG-CURR.txt+, e.g. "7.23"
    # @!attribute [r] tier
    #   @return [String] one of {TIERS}
    # @!attribute [r] platform
    #   @return [String] e.g. "linux-amd64", "macos", "windows-amd64"
    # @!attribute [r] path
    #   @return [String] the engine root directory
    # @!attribute [r] build_date
    #   @return [String, nil] +date:+ from +VERSION.txt+
    # @!attribute [r] git_sha
    #   @return [String, nil] +git:+ from +VERSION.txt+
    # @!attribute [r] sha256
    #   @return [String, nil] digest of the imported zip; nil for directories
    # @!attribute [r] source
    #   @return [String, nil] basename of what was imported
    # @!attribute [r] imported_at
    #   @return [String, nil] ISO 8601 UTC timestamp
    class Installation
      METADATA_FILE = ".talon-engine.yml"
      RECORDED = %i[version tier platform build_date git_sha sha256 source imported_at].freeze

      # @param path [String] an engine root containing {METADATA_FILE}
      # @return [Installation]
      # @raise [InvalidEngine] if the metadata is missing or unreadable
      def self.load(path)
        file = File.join(path, METADATA_FILE)
        data = YAML.safe_load_file(file)
        raise InvalidEngine, "#{file} is not a mapping" unless data.is_a?(Hash)

        new(**RECORDED.to_h { |key| [key, data[key.to_s]] }, path: path)
      rescue Errno::ENOENT, Psych::SyntaxError => e
        raise InvalidEngine, "Can't read engine metadata at #{file}: #{e.message}"
      end

      # @return [String] e.g. "7.23-pro-linux-amd64"
      def id
        "#{version}-#{tier}-#{platform}"
      end

      # @return [Gem::Version]
      def gem_version
        Gem::Version.new(version)
      end

      # @return [String, nil] the build date as YYYY-MM-DD when it parses
      def built_on
        build_date && Time.parse(build_date).strftime("%Y-%m-%d")
      rescue ArgumentError
        build_date
      end

      # Writes {METADATA_FILE} into +dir+ (defaults to {#path}).
      #
      # @param dir [String]
      # @return [void]
      def write_metadata(dir = path)
        data = RECORDED.to_h { |key| [key.to_s, public_send(key)] }
        File.write(File.join(dir, METADATA_FILE), YAML.dump(data))
      end
    end
  end
end
