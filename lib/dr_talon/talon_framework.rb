# frozen_string_literal: true

module DrTalon
  # Support for projects built on the Talon game framework
  # (https://github.com/asimmons91/talon): detecting it, and keeping the
  # requires of generated scenes, components and prefabs in app/main.rb.
  module TalonFramework
    REPOSITORY = "asimmons91/talon"
    GITHUB_KEY = %r{\Agithub:#{Regexp.escape(REPOSITORY)}(/|\z)}
    # Where Talon's entry file is vendored by default.
    REQUIRE = "vendor/talon/talon.rb"

    BEGIN_MARKER = "# >>> talon generate: keep this block; `talon generate` adds requires to it"
    END_MARKER = "# <<< talon generate"
    BLOCK = /^#{Regexp.escape(BEGIN_MARKER)}\n(.*?)^#{Regexp.escape(END_MARKER)}$/m

    # Load order inside the block: superclasses and helpers before the
    # scenes that use them.
    KIND_ORDER = %w[components prefabs scenes].freeze

    # Raised when generating Talon code in a project that doesn't use it.
    class NotUsed < Error; end

    module_function

    # The Talon entry in dependencies.rb: from its GitHub repository, named
    # talon, or a local path through a talon checkout.
    #
    # @param project [Project]
    # @return [Deps::Dependency, nil]
    def dependency(project)
      Deps::Manifest.for(project).dependencies.find do |dependency|
        dependency.key.match?(GITHUB_KEY) ||
          dependency.name == "talon" ||
          (dependency.is_a?(Deps::PathDependency) && dependency.path.split("/").include?("talon"))
      end
    rescue Deps::ManifestError
      nil
    end

    # @param project [Project]
    # @return [Boolean] whether dependencies.rb declares Talon
    def used_by?(project)
      !dependency(project).nil?
    end

    # @param project [Project]
    # @return [String] the game-relative require for Talon's entry file,
    #   wherever the project vendors it
    def require_path(project)
      found = dependency(project)
      found ? "#{found.destination}/talon.rb" : REQUIRE
    end

    # @param project [Project]
    # @return [void]
    # @raise [NotUsed]
    def require_used!(project)
      return if used_by?(project)

      raise NotUsed, "This project doesn't use Talon. Add it with `talon add github:#{REPOSITORY} --path lib`, " \
        "or start from the Talon template with `talon new NAME --template talon`."
    end

    # Adds +line+ to the requires block in +main_rb+, keeping the block in
    # {KIND_ORDER}.
    #
    # @param main_rb [String] path to app/main.rb
    # @param line [String] e.g. require "app/scenes/title.rb"
    # @return [Symbol] +:added+, +:present+ or +:no_block+ (the caller should
    #   tell the user to add the line themselves)
    def add_require(main_rb, line)
      content = File.file?(main_rb) ? File.read(main_rb) : ""
      match = BLOCK.match(content)
      return :no_block unless match

      lines = match[1].lines(chomp: true).reject(&:empty?)
      return :present if lines.include?(line)

      # Other lines keep their order at the top; generated ones follow,
      # grouped by kind and sorted by name.
      sorted = (lines + [line]).each_with_index.sort_by do |entry, index|
        kind = entry[%r{"app/([^/]+)/}, 1]
        kind ? [KIND_ORDER.index(kind) || KIND_ORDER.size, entry] : [-1, index]
      end.map(&:first)
      block = [BEGIN_MARKER, *sorted, END_MARKER].join("\n")
      File.write(main_rb, content.sub(BLOCK) { block })
      :added
    end

    # @param name [String] e.g. "main_menu", "MainMenu", "main-menu"
    # @return [Array(String, String)] the class name and file name
    # @raise [Error] for names that aren't a plain identifier
    def names(name)
      unless name.match?(/\A[A-Za-z][A-Za-z0-9_-]*\z/)
        raise Error, "Invalid name \"#{name}\". Use letters, digits, - and _, starting with a letter (e.g. MainMenu)."
      end

      words = name.gsub(/([a-z\d])([A-Z])/, '\1_\2').split(/[-_]/).reject(&:empty?)
      [words.map { |word| word[0].upcase + word[1..] }.join, words.map(&:downcase).join("_")]
    end
  end
end
