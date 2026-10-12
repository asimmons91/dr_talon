# frozen_string_literal: true

require "fileutils"
require "thor"
require "tmpdir"

module DrTalon
  class CLI < Thor
    # +talon engine ...+: manage the cache of DragonRuby engines.
    class Engine < Thor
      def self.exit_on_failure?
        true
      end

      desc "import PATH", "Add a DragonRuby zip (or an extracted engine directory) to the cache"
      long_desc <<~DESC
        Copies a DragonRuby distribution into talon's engine cache. PATH can be the
        zip as downloaded or a directory it was already extracted to.

        The version is read from CHANGELOG-CURR.txt and the platform from the
        engine directory name. The tier is read from the zip or directory name
        (e.g. dragonruby-pro-linux-amd64.zip); pass --tier when it isn't there.

        DragonRuby only offers its latest release for download, so import every
        version you may want to go back to.
      DESC
      method_option :tier, enum: DrTalon::Engine::TIERS, desc: "License tier, when the file name doesn't say"
      method_option :platform, desc: "Engine platform, e.g. linux-amd64, when the directory name doesn't say"
      method_option :force, type: :boolean, default: false, desc: "Replace a cached engine with the same id"
      def import(path)
        result = with_errors do
          importer = DrTalon::Engine::Importer.new(store, tier: options[:tier], platform: options[:platform], force: options[:force])
          importer.import(path)
        end
        installation = result.installation

        case result.status
        when :unchanged then say "#{installation.id} is already cached from the same zip."
        when :replaced then say "Replaced #{installation.id} at #{installation.path}"
        else say "Imported #{installation.id} to #{installation.path}"
        end
      end

      desc "fetch", "Download the latest engine and add it to the cache"
      long_desc <<~DESC
        Downloads the newest DragonRuby release for this machine and imports it.

        Jam (DragonRuby's free license: Standard's API, web export only) comes
        from the free downloads on DragonRuby's itch.io page; no account needed.

        Pro and Indie come from dragonruby.org with your account's username and
        password, taken from DRAGONRUBY_USERNAME and DRAGONRUBY_PASSWORD, from
        `talon engine login`, or asked for.

        Standard comes from itch.io with butler (https://itch.io/docs/butler/),
        after `butler login`.

        The tier defaults to that of your newest cached engine. DragonRuby only
        offers its latest release, so fetching regularly is how older versions
        stay available in the cache.
      DESC
      method_option :tier, enum: DrTalon::Engine::TIERS, desc: "License tier (default: your newest cached engine's)"
      method_option :keep_zip, type: :boolean, default: false, desc: "Keep the downloaded zip in talon's cache directory"
      def fetch
        tier = options[:tier] || store.latest_native&.tier ||
          raise(Thor::Error, "Pass --tier #{DrTalon::Engine::TIERS.join("|")} (no cached engine to take it from). " \
            "Jam is free and needs no account.")

        result = with_errors { fetch_and_import(tier) }
        installation = result.installation

        if result.status == :unchanged
          say "#{installation.id} is already cached; it's the latest #{tier} release."
        else
          say "Fetched #{installation.id} to #{installation.path}", :green
          say "Use it in a project with `talon engine use #{installation.version}-#{installation.tier}`."
        end
      end

      desc "login", "Save a dragonruby.org login for fetching Pro/Indie engines"
      long_desc <<~DESC
        Asks for your dragonruby.org username and password, checks them against
        the download API, and saves them to credentials.yml in talon's config
        directory, readable only by you (mode 0600). The password is stored in
        plain text there; DRAGONRUBY_USERNAME and DRAGONRUBY_PASSWORD are an
        alternative that stores nothing.
      DESC
      method_option :tier, enum: %w[pro indie], default: "pro", desc: "Tier to check the login against"
      def login
        credentials = ask_credentials
        with_errors { DrTalon::Engine::Fetchers::DragonRubyAPI.new(options[:tier]).verify(credentials) }
        credentials.save(Paths.new.credentials_file)
        say "Saved the login for #{credentials.username} to #{Paths.new.credentials_file} (mode 600)."
      end

      desc "logout", "Delete the saved dragonruby.org login"
      def logout
        path = Paths.new.credentials_file
        say DrTalon::Credentials.delete(path) ? "Deleted #{path}." : "No saved login at #{path}."
      end

      desc "list", "List cached engines"
      def list
        installations = with_errors { store.installations }

        if installations.empty?
          say "No engines cached yet. Add one with `talon engine import <zip>`."
          return
        end

        pinned = pinned_installation
        rows = installations.map do |installation|
          marker = (installation == pinned) ? "*" : ""
          [marker, installation.id, installation.version, installation.tier, installation.platform, installation.built_on.to_s]
        end
        print_table([["", "ID", "VERSION", "TIER", "PLATFORM", "BUILT"], *rows])
        say "\n* pinned by this project" if pinned
      end

      desc "which [ENGINE]", "Print the path of a cached engine (default: this project's pin)"
      def which(spec = nil)
        say with_errors { spec ? store.find(spec) : store.find_native(required_pin) }.path
      end

      desc "use [ENGINE]", "Pin an engine for this project and install it here"
      long_desc <<~DESC
        Writes ENGINE (e.g. 7.23-pro) to .dragonruby-version and copies the cached
        engine into the project, replacing the previously installed one. Without
        ENGINE, installs the version already pinned, e.g. after cloning.

        Only files talon installed before are removed. Files in mygame/ are never
        touched, and other project files that differ from the engine's stop the
        install unless you pass --force.

        Run this in a DragonRuby project: a directory with .dragonruby-version,
        mygame/app/main.rb (full layout) or app/main.rb (game-only layout).
      DESC
      method_option :force, type: :boolean, default: false, desc: "Overwrite project files that differ from the engine's"
      def use(spec = nil)
        project = with_errors { Project.locate }
        installation, previous, result = with_errors do
          requested = spec ? DrTalon::Engine::Spec.parse(spec) : required_pin(project)
          installation = store.find_native(requested, default_tier: project.pin&.tier)
          materializer = DrTalon::Engine::Materializer.new(project)
          previous = materializer.manifest&.engine
          result = materializer.install(installation, force: options[:force])
          DrTalon::Engine::GitIgnore.refresh(project.path(".gitignore"), materializer.manifest.files)
          [installation, previous, result]
        end

        repinned = project.pin&.then { |pin| "#{pin.version}-#{pin.tier}" } != "#{installation.version}-#{installation.tier}"
        project.pin!(installation) if repinned

        details = ["#{result.copied} files"]
        details << "#{result.cloned} as reflinks" if result.cloned.positive?
        if previous == installation.id
          say "Reinstalled #{installation.id} into #{project.root} (#{details.join(", ")})"
        else
          details << "replaced #{previous}" if previous
          say "Installed #{installation.id} into #{project.root} (#{details.join(", ")})"
        end
        say "Pinned #{installation.version}-#{installation.tier} in #{Project::PIN_FILE}" if repinned
      end

      desc "current", "Show the engine this project pins and the one installed"
      def current
        project = with_errors { Project.locate }
        pin = with_errors { project.pin }
        manifest = with_errors { DrTalon::Engine::Materializer.new(project).manifest }

        say "Pinned:    #{pin || "nothing (no #{Project::PIN_FILE})"}"
        say "Installed: #{manifest&.engine || "nothing"}"
      end

      desc "uninstall ENGINE", "Remove an engine from the cache"
      long_desc <<~DESC
        Deletes a cached engine. DragonRuby only offers its latest release for
        download, so the cache may be your only copy of older versions; you're
        asked to confirm unless you pass --yes.
      DESC
      method_option :yes, type: :boolean, aliases: "-y", default: false, desc: "Don't ask for confirmation"
      def uninstall(spec)
        installation = with_errors { store.find(spec) }

        unless options[:yes] || yes?("Remove #{installation.id}? The cache may be your only copy of this version. [y/N]")
          say "Kept #{installation.id}."
          return
        end

        store.remove(installation)
        say "Removed #{installation.id}."
      end

      no_commands do
        def store
          @store ||= DrTalon::Engine::Store.new(Paths.new.engines_dir)
        end

        def required_pin(project = Project.find)
          pin = project&.pin
          return pin if pin

          raise DrTalon::Error, "No engine given and no #{Project::PIN_FILE} found. Pass one, e.g. `7.23-pro`."
        end

        def pinned_installation
          pin = Project.find&.pin
          pin && store.find_native(pin)
        rescue DrTalon::Error
          nil
        end

        def fetch_and_import(tier)
          fetcher = DrTalon::Engine::Fetchers.for(tier)
          credentials = fetcher.credentials? ? DrTalon::Credentials.lookup || ask_credentials(offer_to_save: true) : nil
          say "Downloading the latest #{tier} engine…" unless $stdout.tty?

          path = begin
            fetcher.fetch(credentials: credentials) { |received, total| show_progress(received, total) }
          rescue DrTalon::HTTP::Unauthorized
            source = {env: "DRAGONRUBY_USERNAME/DRAGONRUBY_PASSWORD", file: Paths.new.credentials_file, prompt: "what you typed"}
            raise DrTalon::Error, "dragonruby.org rejected the login from #{source.fetch(credentials.source)}. " \
              "Check it, or run `talon engine login`."
          ensure
            finish_progress
          end

          begin
            DrTalon::Engine::Importer.new(store, tier: tier).import(path)
          ensure
            FileUtils.rm_rf(path) unless options[:keep_zip] && File.file?(path)
          end
        end

        def ask_credentials(offer_to_save: false)
          unless $stdin.tty?
            raise Thor::Error, "No dragonruby.org login. Set #{DrTalon::Credentials::ENV_USERNAME} and " \
              "#{DrTalon::Credentials::ENV_PASSWORD}, or run `talon engine login` in a terminal."
          end

          username = ask("dragonruby.org username:").to_s.strip
          password = ask("dragonruby.org password:", echo: false).to_s
          say ""
          raise Thor::Error, "A username and password are needed." if username.empty? || password.empty?

          credentials = DrTalon::Credentials.new(username: username, password: password, source: :prompt)
          if offer_to_save && yes?("Save this login to #{Paths.new.credentials_file} (mode 600)? [y/N]")
            credentials.save(Paths.new.credentials_file)
          end
          credentials
        end

        def show_progress(received, total)
          return unless $stdout.tty?

          @progress_shown = true
          amount = total ? "#{received * 100 / total}% of #{total / 1_048_576} MB" : "#{received / 1_048_576} MB"
          print "\rDownloading… #{amount}   "
        end

        def finish_progress
          puts if @progress_shown
          @progress_shown = false
        end

        def with_errors
          yield
        rescue DrTalon::Error => e
          raise Thor::Error, e.message
        end
      end
    end
  end
end
