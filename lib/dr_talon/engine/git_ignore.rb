# frozen_string_literal: true

module DrTalon
  module Engine
    # Maintains a marked block in a project's +.gitignore+ that ignores the
    # installed engine, for projects that restore it with +talon engine use+
    # instead of committing it. The block is regenerated on every install so
    # it follows engines that add or drop files.
    module GitIgnore
      BEGIN_MARKER = "# >>> talon: DragonRuby engine, restored by `talon engine use` from .dragonruby-version"
      END_MARKER = "# <<< talon"
      BLOCK = /^#{Regexp.escape(BEGIN_MARKER)}\n.*?^#{Regexp.escape(END_MARKER)}\n?/m

      module_function

      # @param files [Array<String>] project-relative engine files
      # @return [Array<String>] gitignore patterns, top-level entries only
      def patterns(files)
        tops = files.map do |relative|
          top, rest = relative.split("/", 2)
          rest ? "/#{top}/" : "/#{top}"
        end
        ["/.talon/", *tops.uniq.sort]
      end

      # @param path [String] the .gitignore
      # @return [Boolean]
      def block?(path)
        File.file?(path) && File.foreach(path).any? { |line| line.chomp == BEGIN_MARKER }
      end

      # Replaces the block, or appends it if there isn't one.
      #
      # @param path [String] the .gitignore
      # @param files [Array<String>]
      # @return [void]
      def write(path, files)
        block = [BEGIN_MARKER, *patterns(files), END_MARKER].join("\n") + "\n"
        content = File.file?(path) ? File.read(path) : ""

        content =
          if content.match?(BLOCK)
            content.sub(BLOCK) { block }
          else
            [content.empty? ? nil : content.chomp, block].compact.join("\n\n")
          end

        File.write(path, content)
      end

      # Rewrites the block only if the .gitignore already has one, so projects
      # that commit their engine are left alone.
      #
      # @return [Boolean] whether it was rewritten
      def refresh(path, files)
        return false unless block?(path)

        write(path, files)
        true
      end
    end
  end
end
