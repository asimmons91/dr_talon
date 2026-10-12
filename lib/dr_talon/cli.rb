# frozen_string_literal: true

require "thor"
require_relative "cli/engine"
require_relative "generators/new_project"

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

    desc "new PATH", "Create a DragonRuby game (or a library with --lib) with a pinned engine"
    long_desc <<~DESC
      Creates PATH with a game in DragonRuby's layout (mygame/, started from the
      engine's own sample game) or, with --lib, a library whose root is the game
      directory. Pins and installs a cached engine (the newest unless --engine),
      fills in game_metadata.txt, adds editor tooling, then runs git init and
      bundle install.

      You're asked whether to commit the engine unless you pass --commit-engine
      or --no-commit-engine. If not committed, it's gitignored and anyone cloning
      the project restores it with `talon engine use`.
    DESC
    method_options.merge!(Generators::NewProject.class_options)
    def new(path)
      Generators::NewProject.new([path], options, shell: shell).invoke_all
    rescue DrTalon::Error => e
      raise Thor::Error, e.message
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
