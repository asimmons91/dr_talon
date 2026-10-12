# frozen_string_literal: true

require "thor"

module DrTalon
  module Generators
    # +talon generate scene|component|prefab NAME+: a Talon class in
    # app/<kind>s/, a DragonRuby test in tests/<kind>s/, and its require in
    # app/main.rb's managed block.
    class TalonCode < Thor::Group
      include Thor::Actions

      KINDS = %w[scene component prefab].freeze

      argument :kind, type: :string, desc: KINDS.join(", ")
      argument :name, type: :string, desc: "e.g. MainMenu or main_menu"

      class_option :skip_test, type: :boolean, default: false, desc: "Don't create a test"
      class_option :force, type: :boolean, default: false, desc: "Overwrite existing files"

      def self.source_root
        File.expand_path("../templates/talon/generate", __dir__)
      end

      def check
        raise Error, "Unknown kind \"#{kind}\". Expected one of #{KINDS.join(", ")}." unless KINDS.include?(kind)

        TalonFramework.require_used!(project)
        self.destination_root = project.game_dir

        existing = files.select { |path| File.exist?(File.join(destination_root, path)) }
        return if existing.empty? || options[:force]

        raise Error, "#{existing.join(" and ")} already exist#{"s" if existing.one?}. Pass --force to overwrite."
      end

      def create_code
        template "#{kind}.rb.tt", code_path, force: options[:force]
      end

      def create_test
        template "#{kind}_tests.rb.tt", test_path, force: options[:force] unless options[:skip_test]
      end

      def add_require
        main = File.join(destination_root, "app", "main.rb")
        line = %(require "#{file_require}")

        case TalonFramework.add_require(main, line)
        when :added then say_status :update, "app/main.rb (#{line})"
        when :present then say_status :identical, "app/main.rb (#{line})", :blue
        else
          say "\nAdd this to app/main.rb (it has no `talon generate` block):\n  #{line}"
        end
      end

      no_commands do
        def project
          @project ||= Project.locate
        end

        def class_name
          TalonFramework.names(name).first
        end

        def file_name
          TalonFramework.names(name).last
        end

        def code_path
          "app/#{kind}s/#{file_name}.rb"
        end

        def test_path
          "tests/#{kind}s/#{file_name}_tests.rb"
        end

        def file_require
          code_path
        end

        def talon_require
          TalonFramework.require_path(project)
        end

        def files
          options[:skip_test] ? [code_path] : [code_path, test_path]
        end
      end
    end
  end
end
