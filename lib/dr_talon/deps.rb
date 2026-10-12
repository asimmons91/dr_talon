# frozen_string_literal: true

module DrTalon
  # DragonRuby dependencies: declared in +dependencies.rb+ in the game
  # directory, vendored into +vendor/+, locked below +__END__+.
  module Deps
    # Downloading or resolving a dependency failed.
    class FetchError < Error; end

    # +dependencies.rb+ is invalid.
    class ManifestError < Error; end

    # Vendored files were changed outside talon.
    class ModifiedError < Error; end

    # Parses a `talon add` source: github:owner/repo, git:URL, url:URL or
    # path:DIR.
    #
    # @return [Array(Symbol, String)] the DSL method and its first argument
    # @raise [Error]
    def self.parse_source(source)
      kind, value = source.to_s.split(":", 2)
      if %w[github git url path].include?(kind) && !value.to_s.empty?
        return [kind.to_sym, value] unless kind == "github" && !value.match?(%r{\A[\w.-]+/[\w.-]+\z})
      end

      raise Error, "Unknown source #{source.inspect}. Use github:owner/repo, git:URL, url:URL or path:DIR."
    end

    # A dependencies.rb line for `talon add`.
    #
    # @return [String]
    def self.declaration(kind, value, path: nil, ref: nil, as: nil)
      options = {path: path, ref: ref, as: as}.compact
      options.delete(:path) if kind == :url || kind == :path
      options.delete(:ref) if kind == :url || kind == :path
      [%(#{kind} #{value.inspect}), *options.map { |key, val| "#{key}: #{val.inspect}" }].join(", ")
    end

    # The line to require a vendored dependency from game code.
    #
    # @param project [Project]
    # @param dependency [Dependency]
    # @return [String, nil]
    def self.require_hint(project, dependency)
      target = File.join(project.game_dir, dependency.destination)
      return %(require "#{dependency.destination}") if File.file?(target)
      return nil unless File.directory?(target)

      base = dependency.name.delete_suffix(".rb").tr("-", "_")
      entry = ["#{base}.rb", "lib/#{base}.rb", "main.rb"].find { |candidate| File.file?(File.join(target, candidate)) }
      entry ||= Dir.glob("*.rb", base: target).min
      entry && %(require "#{dependency.destination}/#{entry}")
    end
  end
end

require_relative "deps/git"
require_relative "deps/tree"
require_relative "deps/dependency"
require_relative "deps/manifest"
require_relative "deps/installer"
