# frozen_string_literal: true

require "thor"

module DrTalon
  class CLI < Thor
    # +talon generate ...+: Talon framework code, Rails-generator style.
    class Generate < Thor
      def self.exit_on_failure?
        true
      end

      {
        "scene" => "A Talon::Scene: one screen or level, entered with game.change_scene",
        "component" => "A Talon::Component: behaviour attached to game objects with go.add",
        "prefab" => "A prefab: a reusable game object setup, passed to spawn"
      }.each do |kind, description|
        desc "#{kind} NAME", description
        method_option :skip_test, type: :boolean, default: false, desc: "Don't create a test"
        method_option :force, type: :boolean, default: false, desc: "Overwrite existing files"
        define_method(kind) do |name|
          Generators::TalonCode.new([kind, name], options, shell: shell).invoke_all
        rescue DrTalon::Error => e
          raise Thor::Error, e.message
        end
      end
    end
  end
end
