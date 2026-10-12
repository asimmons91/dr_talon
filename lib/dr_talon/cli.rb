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

    # `run` is reserved by Thor, so the command method has another name.
    map "run" => :run_game
    stop_on_unknown_option! :run_game

    desc "run [ARGS...]", "Run the game (extra arguments go to dragonruby, e.g. --record)"
    def run_game(*args)
      exec_in_project { |runner| runner.run_command(args) }
    end

    desc "test [FILES...]", "Run DragonRuby tests (*_tests.rb in test/ and tests/ by default)"
    long_desc <<~DESC
      Runs each test file with `dragonruby --test` and reports passes and
      failures. DragonRuby always exits 0, so talon reads its output and exits
      non-zero when a test fails, a file doesn't load, a file has no tests, or a
      run times out.

      FILES may be files or directories inside the game directory. By default
      every *_tests.rb under test/ and tests/ runs. Tests run without a window
      unless you pass --no-headless.
    DESC
    method_option :headless, type: :boolean, default: true, desc: "Run without a window or audio (SDL dummy drivers)"
    method_option :timeout, type: :numeric, default: 120, desc: "Seconds before a test file's run is stopped"
    method_option :verbose, type: :boolean, aliases: "-v", default: false, desc: "Print DragonRuby's full output"
    def test(*paths)
      project = with_errors { Project.locate }
      runner = Runner.new(project)
      files = with_errors { runner.test_files(paths) }
      if files.empty?
        raise Thor::Error, "No #{Runner::TEST_PATTERN} files in #{Runner::TEST_DIRS.join(" or ")} under #{project.game_dir}."
      end

      reports = files.map do |file|
        report = with_errors { runner.run_test(file, timeout: options[:timeout], headless: options[:headless]) }
        print_test_report(file, report)
        report
      end

      print_test_summary(reports)
      exit(1) unless reports.all?(&:passed?)
    rescue Interrupt
      say "\nInterrupted.", :yellow
      exit(130)
    end

    desc "build [ARGS...]", "Package the game for every platform into builds/ (dragonruby-publish --only-package)"
    stop_on_unknown_option! :build
    def build(*args)
      exec_in_project do |runner, project|
        unset = Doctor.unset_metadata(project)
        if unset&.any?
          say "Warning: game_metadata.txt doesn't set #{unset.join(", ")}; dragonruby-publish needs them.", :yellow
        end
        runner.build_command(args)
      end
    end

    desc "serve [DIR]", "Serve an HTML5 build locally with dragonruby-httpd (default: the newest in builds/)"
    method_option :port, type: :numeric, default: 8080, desc: "Port to listen on"
    def serve(dir = nil)
      exec_in_project do |runner|
        dir ||= runner.html5_build || raise(Error, "No HTML5 build in builds/. Run `talon build` first.")
        say "Serving #{dir} at http://localhost:#{options[:port]}/"
        runner.serve_command(dir, options[:port])
      end
    end

    desc "clean", "Delete builds/, logs/, tmp/ and errors/ (and their mygame/ counterparts)"
    def clean
      project = with_errors { Project.locate }
      removed = Runner.new(project).clean
      if removed.empty?
        say "Nothing to clean."
      else
        removed.each { |dir| say_status :remove, dir, :red }
      end
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

    no_commands do
      def with_errors
        yield
      rescue DrTalon::Error => e
        raise Thor::Error, e.message
      end

      # Yields the project's runner (and project) for a command line, then
      # replaces this process with it so signals and the exit status are the
      # engine's own.
      def exec_in_project
        project = with_errors { Project.locate }
        argv = with_errors { yield Runner.new(project), project }
        Runner.exec_process(argv, chdir: project.root)
      end

      def print_test_report(file, report)
        counts = ["#{report.passed} passed"]
        counts << "#{report.failed} failed" if report.failed.positive?
        counts << "#{report.inconclusive} inconclusive" if report.inconclusive.positive?

        case report.status
        when :passed then say "✓ #{file} (#{counts.join(", ")})", :green
        when :failed then say "✗ #{file} (#{counts.join(", ")})", :red
        when :error then say "✗ #{file} didn't load or raised outside a test", :red
        when :no_tests then say "✗ #{file} has no tests (methods named test_*)", :red
        when :timeout then say "✗ #{file} timed out after #{options[:timeout]}s", :red
        end

        if options[:verbose]
          say report.output
        elsif !report.details.empty?
          say report.details.gsub(/^/, "    ")
        end
      end

      def print_test_summary(reports)
        passed = reports.sum(&:passed)
        failed = reports.sum(&:failed)
        bad_files = reports.count { |report| !report.passed? }
        summary = "#{plural(reports.size, "file")}, #{plural(passed, "test")} passed"

        say ""
        if bad_files.zero?
          say summary, :green
        else
          say "#{summary}, #{failed} failed, #{plural(bad_files, "file")} with problems", :red
        end
      end

      def plural(count, word)
        "#{count} #{word}#{"s" unless count == 1}"
      end
    end
  end
end
