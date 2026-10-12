# frozen_string_literal: true

require "thor"

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
  end
end
