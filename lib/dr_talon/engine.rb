# frozen_string_literal: true

require "rbconfig"

module DrTalon
  # Cached DragonRuby engines: identifying, importing and looking them up.
  module Engine
    TIERS = %w[standard indie pro].freeze

    # The engine path doesn't look like a DragonRuby distribution, or a detail
    # such as its version can't be determined.
    class InvalidEngine < Error; end

    # No cached engine matches a requested spec.
    class NotFound < Error; end

    # More than one cached engine matches a requested spec.
    class Ambiguous < Error; end

    # An engine with the same id is already cached.
    class AlreadyInstalled < Error; end

    # The DragonRuby platform name for the machine talon is running on, as used
    # in DragonRuby's zip and directory names (+dragonruby-linux-amd64+).
    #
    # @param host_os [String]
    # @param host_cpu [String]
    # @return [String]
    def self.host_platform(host_os: RbConfig::CONFIG["host_os"], host_cpu: RbConfig::CONFIG["host_cpu"])
      arch = /arm|aarch64/.match?(host_cpu) ? "arm64" : "amd64"

      case host_os
      when /darwin/ then "macos"
      when /mswin|mingw|cygwin/ then "windows-#{arch}"
      else "linux-#{arch}"
      end
    end
  end
end

require_relative "engine/installation"
require_relative "engine/spec"
require_relative "engine/inspector"
require_relative "engine/store"
require_relative "engine/importer"
