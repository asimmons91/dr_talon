# frozen_string_literal: true

require "fileutils"
require "yaml"

module DrTalon
  module Engine
    # Copies a cached engine into a {Project} and records what it placed in a
    # manifest, so switching engines later removes exactly those files and
    # never touches the game or anything else in the project.
    class Materializer
      MANIFEST = File.join(".talon", "engine.yml")

      # Top-level files a +:game_only+ project gets: enough to run the game
      # and its tests. Windows builds may also need the DLLs next to the exe.
      GAME_ONLY_FILES = %w[dragonruby dragonruby.exe font.ttf].freeze

      # Files talon never copies into a project.
      SKIPPED = [Installation::METADATA_FILE].freeze

      # File names never copied, wherever they are (DragonRuby's zips include
      # macOS Finder metadata).
      SKIPPED_NAMES = %w[.DS_Store].freeze

      # Project files that differ from the engine's and aren't from a previous
      # install, so overwriting them could lose someone's work.
      class Conflict < Error; end

      # @!attribute [r] engine
      #   @return [String, nil] the installed {Installation#id}
      # @!attribute [r] files
      #   @return [Array<String>] project-relative paths talon placed
      Manifest = Data.define(:engine, :files)

      # @!attribute [r] copied
      #   @return [Integer] files written
      # @!attribute [r] removed
      #   @return [Integer] files from the previous engine that were deleted
      # @!attribute [r] cloned
      #   @return [Integer] how many of the copies were reflinks
      Result = Data.define(:copied, :removed, :cloned)

      # @param project [Project]
      def initialize(project)
        @project = project
      end

      # @return [Manifest, nil]
      def manifest
        path = @project.path(MANIFEST)
        return nil unless File.file?(path)

        data = YAML.safe_load_file(path)
        raise Error, "#{MANIFEST} is not a mapping" unless data.is_a?(Hash)

        files = Array(data["files"]).map(&:to_s)
        # Entries are deleted on the next install, so never trust one that
        # points outside the project.
        unsafe = files.find { |relative| relative.start_with?("/") || relative.split(%r{[/\\]}).include?("..") }
        raise Error, "#{MANIFEST} lists a path outside the project: #{unsafe}" if unsafe

        Manifest.new(engine: data["engine"], files: files)
      rescue Psych::SyntaxError => e
        raise Error, "Can't read #{MANIFEST}: #{e.message}"
      end

      # The engine files a project of this layout gets, relative to both the
      # engine root and the project root.
      #
      # @param installation [Installation]
      # @return [Array<String>]
      def files_for(installation)
        all = Dir.glob("**/*", File::FNM_DOTMATCH, base: installation.path).select do |relative|
          path = File.join(installation.path, relative)
          (File.file?(path) || File.symlink?(path)) && !File.basename(relative).match?(/\A\.\.?\z/)
        end
        all.reject! do |relative|
          relative.start_with?("mygame/") || SKIPPED.include?(relative) || SKIPPED_NAMES.include?(File.basename(relative))
        end

        if @project.layout == :game_only
          all.select! { |relative| GAME_ONLY_FILES.include?(relative) || relative.match?(%r{\A[^/]+\.dll\z}i) }
        end

        all.sort
      end

      # Project paths that would be overwritten but weren't placed by talon
      # and differ from the engine's copy. Identical files are adopted
      # silently, which covers projects started from an unzipped engine.
      #
      # @param installation [Installation]
      # @return [Array<String>]
      def conflicts(installation)
        previous = manifest&.files || []

        (files_for(installation) - previous).select do |relative|
          target = @project.path(relative)
          next false unless File.exist?(target) || File.symlink?(target)

          source = File.join(installation.path, relative)
          File.symlink?(target) || !File.file?(target) || !FileUtils.compare_file(source, target)
        end
      end

      # Removes the previous engine's files and copies in +installation+.
      #
      # @param installation [Installation]
      # @param force [Boolean] overwrite {#conflicts}
      # @return [Result]
      # @raise [Conflict]
      def install(installation, force: false)
        conflicting = conflicts(installation)
        if conflicting.any? && !force
          listed = conflicting.first(10).map { |relative| "  #{relative}" }.join("\n")
          more = (conflicting.size > 10) ? "\n  ...and #{conflicting.size - 10} more" : ""
          raise Conflict, "These project files differ from #{installation.id}'s and weren't installed by talon:\n" \
            "#{listed}#{more}\nMove them aside, or pass --force to overwrite them."
        end

        files = files_for(installation)
        removed = remove_files(manifest&.files || [])

        # Record the new files before copying, so a failed copy can be cleaned
        # up by the next install rather than reported as conflicts.
        write_manifest(Manifest.new(engine: installation.id, files: files))

        cloned = files.count do |relative|
          target = @project.path(relative)
          FileUtils.mkdir_p(File.dirname(target))
          FileCopy.copy(File.join(installation.path, relative), target)
        end

        Result.new(copied: files.size, removed: removed, cloned: cloned)
      end

      private

      def remove_files(files)
        removed = files.count do |relative|
          target = @project.path(relative)
          next false unless File.exist?(target) || File.symlink?(target)

          File.unlink(target)
          true
        end

        prune_empty_dirs(files)
        removed
      end

      # Deletes directories emptied by {#remove_files}, deepest first, without
      # ever going above the project root.
      def prune_empty_dirs(files)
        dirs = files.flat_map do |relative|
          parts = File.dirname(relative).split("/")
          parts.each_index.map { |i| parts[0..i].join("/") }
        end
        dirs.uniq.reject { |dir| dir == "." }.sort_by { |dir| -dir.count("/") }.each do |dir|
          path = @project.path(dir)
          Dir.rmdir(path) if File.directory?(path) && Dir.empty?(path)
        end
      end

      def write_manifest(manifest)
        path = @project.path(MANIFEST)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, YAML.dump({"engine" => manifest.engine, "files" => manifest.files}))
      end
    end
  end
end
