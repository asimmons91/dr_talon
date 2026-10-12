# frozen_string_literal: true

require "thor"

module DrTalon
  module Generators
    # +talon new PATH+: creates a game (+bare+ template, DragonRuby's full
    # layout) or a library (+lib+ template, game-only layout) with a pinned,
    # installed engine.
    #
    # Each public method is a step, run in order by {Thor::Group#invoke_all}.
    class NewProject < Thor::Group
      include Thor::Actions

      TEMPLATES = %w[bare lib].freeze
      NAME_PATTERN = /\A[A-Za-z][A-Za-z0-9_-]*\z/

      argument :path, type: :string, desc: "Directory to create; its name is the project name"

      class_option :template, type: :string, desc: "bare (a game) or lib (a library); default from config.yml, else bare"
      class_option :lib, type: :boolean, default: false, desc: "Shorthand for --template lib"
      class_option :engine, type: :string, desc: "Engine to pin, e.g. 7.23-pro (default: the newest cached)"
      class_option :commit_engine, type: :boolean,
        desc: "Commit the engine to git instead of ignoring it and restoring with `talon engine use` (asked if omitted)"
      class_option :title, type: :string, desc: "Game title for game_metadata.txt (default: from the name)"
      class_option :dev_id, type: :string, desc: "itch.io username for game_metadata.txt (default: from config.yml)"
      class_option :dev_title, type: :string, desc: "Developer display name for game_metadata.txt (default: from config.yml)"
      class_option :skip_git, type: :boolean, default: false, desc: "Don't run git init"
      class_option :skip_bundle, type: :boolean, default: false, desc: "Don't run bundle install"

      def self.source_root
        File.expand_path("../templates", __dir__)
      end

      def check_destination
        raise Error, "Invalid project name \"#{name}\". Use letters, digits, - and _, starting with a letter." unless NAME_PATTERN.match?(name)
        raise Error, "Unknown template \"#{template_name}\". Expected one of #{TEMPLATES.join(", ")}." unless TEMPLATES.include?(template_name)

        root = File.expand_path(path)
        raise Error, "#{root} already exists and isn't empty." if File.exist?(root) && !(File.directory?(root) && Dir.empty?(root))

        self.destination_root = root
      end

      def resolve_engine
        engine
      end

      def ask_about_committing_engine
        commit_engine?
      end

      def create_game
        (layout == :full) ? copy_stock_game : create_library
      end

      def create_tooling
        template "shared/Gemfile.tt", "Gemfile"
        template "shared/editorconfig.tt", ".editorconfig"
        template "shared/gitignore.tt", ".gitignore"
        template "shared/README.md.tt", "README.md"
        template "#{template_name}/rubocop.yml.tt", ".rubocop.yml"
        template "#{template_name}/solargraph.yml.tt", ".solargraph.yml"
      end

      def fill_metadata
        return unless layout == :full

        file = File.join(destination_root, "mygame", "metadata", "game_metadata.txt")
        return unless File.file?(file)

        values = {
          "devid" => options[:dev_id] || config.dev_id,
          "devtitle" => options[:dev_title] || config.dev_title,
          "gameid" => name.downcase.tr("_", "-"),
          "gametitle" => title,
          "version" => "0.1",
          "icon" => "metadata/icon.png"
        }.compact

        content = values.reduce(File.read(file)) do |text, (key, value)|
          # Set the first assignment, uncommenting DragonRuby's "# key=..." form.
          text.sub(/^[ \t]*(?:#[ \t]*)?#{Regexp.escape(key)}=.*$/) { "#{key}=#{value}" }
        end
        File.write(file, content)
        say_status :update, "mygame/metadata/game_metadata.txt"
      end

      def install_engine
        project = Project.new(destination_root)
        materializer = Engine::Materializer.new(project)
        result = materializer.install(engine)
        project.pin!(engine)
        say_status :engine, "#{engine.id} (#{result.copied} files)"
        say_status :create, Project::PIN_FILE

        Engine::GitIgnore.write(File.join(destination_root, ".gitignore"), materializer.manifest.files) unless commit_engine?
      end

      def git_init
        return if options[:skip_git]
        return say_status(:skip, "git init (git not found)", :yellow) unless executable?("git")

        inside(destination_root) { run "git init --quiet", abort_on_failure: false }
      end

      def bundle_install
        return if options[:skip_bundle]
        return say_status(:skip, "bundle install (bundler not found)", :yellow) unless executable?("bundle")

        # Run against the new Gemfile, not whichever bundle talon runs in.
        if defined?(Bundler)
          Bundler.with_unbundled_env { bundle_in_destination }
        else
          bundle_in_destination
        end
      end

      def print_next_steps
        relative = path
        say ""
        say "Created #{name} with DragonRuby #{engine.id}.", :green
        say "  cd #{relative}"
        say((layout == :full) ? "  ./dragonruby mygame" : "  ./dragonruby . --test test/#{file_name}_tests.rb")
        say "  talon doctor"
      end

      no_commands do
        def name
          File.basename(File.expand_path(path))
        end

        # @return [String] the name as a Ruby file name: my-lib -> my_lib
        def file_name
          name.tr("-", "_")
        end

        def module_name
          name.split(/[-_]/).map { |part| part[0].upcase + part[1..] }.join
        end

        def title
          options[:title] || name.split(/[-_]/).map(&:capitalize).join(" ")
        end

        def template_name
          @template_name ||= options[:lib] ? "lib" : (options[:template] || config.default_template)
        end

        def layout
          (template_name == "lib") ? :game_only : :full
        end

        def dependencies_hint
          (layout == :full) ? "mygame/vendor/" : "vendor/"
        end

        def engine
          @engine ||=
            if options[:engine]
              store.find_native(Engine::Spec.parse(options[:engine]))
            else
              store.latest_native || raise(Engine::NotFound,
                "No #{Engine.host_platform} engine is cached. Import one first: talon engine import <zip>")
            end
        end

        # Asked once unless --commit-engine/--no-commit-engine was given.
        # Libraries default to not committing: DragonRuby asks that public
        # repos not include its tooling.
        def commit_engine?
          return @commit_engine unless @commit_engine.nil?

          @commit_engine =
            if !options[:commit_engine].nil?
              options[:commit_engine]
            elsif layout == :game_only
              false
            else
              yes?("Commit the DragonRuby engine to git? DragonRuby recommends it for private/commercial games. " \
                "If not, it's gitignored and restored with `talon engine use`. [y/N]")
            end
        end

        def config
          @config ||= Config.load
        end

        def store
          @store ||= Engine::Store.new(Paths.new.engines_dir)
        end
      end

      private

      def copy_stock_game
        source = File.join(engine.path, "mygame")
        raise Engine::InvalidEngine, "#{engine.id} has no mygame/ to start from." unless File.directory?(source)

        Dir.glob("**/*", File::FNM_DOTMATCH, base: source).sort.each do |relative|
          next if File.basename(relative).match?(/\A\.\.?\z/) || File.basename(relative) == ".DS_Store"

          from = File.join(source, relative)
          to = File.join(destination_root, "mygame", relative)
          if File.directory?(from)
            FileUtils.mkdir_p(to)
          else
            FileUtils.mkdir_p(File.dirname(to))
            FileCopy.copy(from, to)
          end
        end
        say_status :create, "mygame (from #{engine.id})"
      end

      def create_library
        template "lib/app/main.rb.tt", "app/main.rb"
        template "lib/lib/library.rb.tt", "lib/#{file_name}.rb"
        template "lib/lib/version.rb.tt", "lib/#{file_name}/version.rb"
        template "lib/test/test_helper.rb.tt", "test/test_helper.rb"
        template "lib/test/tests.rb.tt", "test/#{file_name}_tests.rb"
      end

      def bundle_in_destination
        inside(destination_root) { run "bundle install --quiet", abort_on_failure: false }
      end

      def executable?(command)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
          File.executable?(File.join(dir, command)) && !File.directory?(File.join(dir, command))
        end
      end
    end
  end
end
