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

    desc "doctor", "Check this project's engine, game and metadata"
    def doctor
      project = Project.locate
      store = DrTalon::Engine::Store.new(Paths.new.engines_dir)
      checks = Doctor.new(project, store).checks

      symbols = {ok: "✓", warning: "!", error: "✗"}
      checks.each { |check| say "#{symbols.fetch(check.status)} #{check.message}" }

      errors = checks.count { |check| check.status == :error }
      raise Thor::Error, "#{errors} problem#{"s" unless errors == 1} found" if errors.positive?
    rescue DrTalon::Error => e
      raise Thor::Error, e.message
    end

    desc "engine SUBCOMMAND", "Manage cached DragonRuby engines"
    subcommand "engine", Engine
  end
end
