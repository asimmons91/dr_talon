# frozen_string_literal: true

require "thor"
require_relative "cli/engine"

module DrTalon
  # Entry point for the +talon+ executable.
  class CLI < Thor
    package_name "talon"

    map %w[-v --version] => :version

    # Exit with a non-zero status on errors and unknown commands.
    def self.exit_on_failure?
      true
    end

    desc "version", "Print the talon version"
    def version
      say "talon #{VERSION}"
    end

    desc "engine SUBCOMMAND", "Manage cached DragonRuby engines"
    subcommand "engine", Engine
  end
end
