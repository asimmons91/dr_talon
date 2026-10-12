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

        rows = installations.map do |installation|
          [installation.id, installation.version, installation.tier, installation.platform, installation.built_on.to_s]
        end
        print_table([%w[ID VERSION TIER PLATFORM BUILT], *rows])
      end

      desc "which ENGINE", "Print the path of a cached engine (e.g. 7.23 or 7.23-pro)"
      def which(spec)
        say with_errors { store.find(spec) }.path
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

        def with_errors
          yield
        rescue DrTalon::Error => e
          raise Thor::Error, e.message
        end
      end
    end
  end
end
