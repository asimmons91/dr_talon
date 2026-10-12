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

    desc "install", "Install the pinned engine (if missing) and the dependencies in dependencies.rb"
    long_desc <<~DESC
      Run after cloning a project. Installs the engine pinned in .dragonruby-version
      if it isn't installed yet, then vendors every dependency in the game
      directory's dependencies.rb at its locked version. Dependencies without a
      lock yet are resolved and locked.

      Vendored files edited since talon installed them stop the install unless
      you pass --force.
    DESC
    method_option :force, type: :boolean, default: false, desc: "Replace or delete locally modified vendored files"
    def install
      project = with_errors { Project.locate }
      with_errors do
        engine = install_pinned_engine(project)
        say "Installed engine #{engine.id}" if engine
      end
      run_dependency_install(project)
    end

    desc "update [NAMES...]", "Re-resolve dependencies (all, or the named ones) and install the new versions"
    method_option :force, type: :boolean, default: false, desc: "Replace locally modified vendored files"
    def update(*names)
      run_dependency_install(with_errors { Project.locate }, update: names.empty? || names)
    end

    desc "add SOURCE", "Add a dependency to dependencies.rb and install it"
    long_desc <<~DESC
      SOURCE is one of:

        github:OWNER/REPO   a GitHub repository (downloaded as a tarball)
        git:URL             any git repository
        url:URL             a single file
        path:DIR            a local file or directory, copied on every install

      Examples:

        talon add github:asimmons91/talon --path lib
        talon add github:someone/tweens --ref v1.2.0 --as tweens
        talon add url:https://example.com/easing.rb

      The files are vendored into vendor/NAME in the game directory.
    DESC
    method_option :path, type: :string, desc: "File or directory inside the repository to vendor (default: all of it)"
    method_option :ref, type: :string, desc: "Branch, tag or full commit SHA (default: the default branch)"
    method_option :as, type: :string, desc: "Name, and directory under vendor/ (default: from the source)"
    def add(source)
      project = with_errors { Project.locate }
      manifest = with_errors { Deps::Manifest.for(project) }
      original = File.file?(manifest.path) ? File.read(manifest.path) : nil
      kind, value = with_errors { Deps.parse_source(source) }
      line = Deps.declaration(kind, value, path: options[:path], ref: options[:ref], as: options[:as])

      begin
        with_errors { manifest.add(line) }
        say_status :add, "#{relative_to_root(project, manifest.path)}: #{line}"
        run_dependency_install(project)
      rescue Thor::Error, SystemExit
        original ? File.write(manifest.path, original) : FileUtils.rm_f(manifest.path)
        raise
      end

      dependency = Deps::Manifest.for(project).dependencies.last
      hint = Deps.require_hint(project, dependency)
      say "\nLoad it from your game with:\n  #{hint}" if hint
    end

    desc "remove NAME", "Remove a dependency from dependencies.rb and delete its vendored files"
    method_option :force, type: :boolean, default: false, desc: "Delete the files even if they were modified"
    def remove(name)
      project = with_errors { Project.locate }
      manifest = with_errors { Deps::Manifest.for(project) }
      dependency = manifest.find(name) || raise(Thor::Error, "No dependency named #{name} in #{Deps::Manifest::FILE}.")

      with_errors { manifest.remove(dependency) }
      say_status :remove, "#{relative_to_root(project, manifest.path)}: #{dependency.name}", :red
      run_dependency_install(project)
    end

    desc "outdated", "List dependencies whose branch, tag or URL now points at something newer"
    def outdated
      project = with_errors { Project.locate }
      rows = with_errors { Deps::Installer.new(project).outdated }

      if rows.empty?
        say "All dependencies are up to date."
      else
        table = rows.map do |row|
          [row[:dependency].name, short(row[:locked]) || "(not locked)", short(row[:latest]), row[:dependency].ref || "default branch"]
        end
        print_table([%w[NAME LOCKED LATEST REF], *table])
        say "\nRun `talon update NAME` to install the latest."
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

      def install_pinned_engine(project)
        pin = project.pin or return nil
        installation = DrTalon::Engine::Store.new(Paths.new.engines_dir).find_native(pin)
        materializer = DrTalon::Engine::Materializer.new(project)
        return nil if materializer.manifest&.engine == installation.id

        materializer.install(installation)
        DrTalon::Engine::GitIgnore.refresh(project.path(".gitignore"), materializer.manifest.files)
        installation
      end

      def run_dependency_install(project, update: nil)
        manifest = with_errors { Deps::Manifest.for(project) }
        unless manifest.exist?
          say "No #{Deps::Manifest::FILE} in #{relative_to_root(project, project.game_dir)}/; add a dependency with `talon add`."
          return
        end
        if manifest.foodchain_locks
          say "Found Foodchain's ETag locks; talon re-resolves those dependencies and locks them to commits.", :yellow
        end

        changes = with_errors { Deps::Installer.new(project, force: options[:force]).install(update: update) }
        changes.each { |change| say_change(change) }
        say "No dependencies in #{Deps::Manifest::FILE}." if changes.empty?
      end

      def say_change(change)
        source = change.dependency && "#{change.dependency.key} @ #{short(change.commit) || "local"}"
        case change.action
        when :installed then say_status :install, "#{change.name} (#{source})"
        when :updated then say_status :update, "#{change.name} #{short(change.previous) || "-"} → #{short(change.commit) || "local"}"
        when :unchanged then say_status :using, "#{change.name} (#{source})", :blue
        when :restored then say_status :restore, "#{change.name} (#{source}); local changes replaced", :yellow
        when :removed then say_status :remove, change.name, :red
        when :kept then say_status :kept, "#{change.name}: no longer declared, but modified locally; delete it yourself", :yellow
        end
      end

      # 7 characters of a commit, or the first 8 hex digits of a sha256.
      def short(commit)
        return nil unless commit

        commit.start_with?("sha256:") ? commit[0, 15] : commit[0, 7]
      end

      def relative_to_root(project, path)
        path.delete_prefix("#{project.root}/")
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
