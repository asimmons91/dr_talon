# frozen_string_literal: true

require "thor"

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
        say with_errors { spec ? store.find(spec) : find_for_host(required_pin) }.path
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
          installation = find_for_host(requested, project.pin&.tier)
          materializer = DrTalon::Engine::Materializer.new(project)
          previous = materializer.manifest&.engine
          [installation, previous, materializer.install(installation, force: options[:force])]
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

        # Resolves +spec+ to an engine for this machine, since a project can
        # only run its host's build. A missing tier defaults to +tier+.
        def find_for_host(spec, tier = nil)
          host = DrTalon::Engine.host_platform
          if spec.platform && spec.platform != host
            raise DrTalon::Error, "This machine runs #{host} engines; #{spec} is for #{spec.platform}."
          end

          store.find(DrTalon::Engine::Spec.new(version: spec.version, tier: spec.tier || tier, platform: host))
        end

        def required_pin(project = Project.find)
          pin = project&.pin
          return pin if pin

          raise DrTalon::Error, "No engine given and no #{Project::PIN_FILE} found. Pass one, e.g. `7.23-pro`."
        end

        def pinned_installation
          pin = Project.find&.pin
          pin && find_for_host(pin)
        rescue DrTalon::Error
          nil
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
