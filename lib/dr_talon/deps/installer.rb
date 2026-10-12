# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module DrTalon
  module Deps
    # Brings vendored files in line with +dependencies.rb+ and its locks.
    #
    # - Locked dependencies install their locked commit; new ones, ones whose
    #   ref or destination changed, and ones being updated are resolved again.
    # - Vendored files are replaced only when they're unchanged since talon
    #   wrote them (or identical to what would be written); otherwise the
    #   install stops unless +force+.
    # - Dependencies removed from the manifest have their files deleted.
    # - Locks are written even when a later dependency fails, so finished work
    #   isn't reported as modified next time.
    class Installer
      # @!attribute [r] name
      #   @return [String]
      # @!attribute [r] action
      #   @return [Symbol] +:installed+, +:updated+, +:unchanged+, +:restored+
      #     (local changes replaced with --force), +:removed+ or +:kept+
      #     (removed from the manifest but locally modified)
      # @!attribute [r] dependency
      #   @return [Dependency, nil] nil for removals
      # @!attribute [r] commit
      #   @return [String, nil]
      # @!attribute [r] previous
      #   @return [String, nil] the commit before an update
      Change = Data.define(:name, :action, :dependency, :commit, :previous)

      # @param project [Project]
      # @param context [Context]
      # @param force [Boolean] overwrite or delete locally modified vendored files
      def initialize(project, context: Context.default, force: false)
        @project = project
        @context = context
        @force = force
      end

      # @param update [Array<String>, true, nil] names to re-resolve, or true for all
      # @return [Array<Change>]
      # @raise [ModifiedError] if vendored files were edited and +force+ is off
      # @raise [Error] if +update+ names an unknown dependency
      def install(update: nil)
        manifest = Manifest.for(@project)
        check_update_names!(manifest, update)
        previous = manifest.locks.to_h { |lock| [lock.key, lock] }
        written = {}
        changes = []

        begin
          manifest.dependencies.each do |dependency|
            lock, change = install_dependency(dependency, previous[dependency.key], updating?(dependency, update))
            written[dependency.key] = lock
            changes << change
          end

          (previous.keys - manifest.dependencies.map(&:key)).each do |key|
            changes << remove(previous[key])
            previous.delete(key)
          end
        ensure
          # Keep locks for anything not reached (including removals not done
          # yet), so a failure doesn't forget them.
          unreached = previous.reject { |key, _| written.key?(key) }
          manifest.write_locks(written.values + unreached.values) if manifest.exist? || written.any?
        end

        changes
      end

      # @return [Array<Hash>] +dependency+, +locked+ and +latest+ commits of
      #   dependencies whose source has moved on
      def outdated
        manifest = Manifest.for(@project)
        locks = manifest.locks.to_h { |lock| [lock.key, lock] }

        manifest.dependencies.select(&:lockable?).filter_map do |dependency|
          locked = locks[dependency.key]&.commit
          latest = dependency.resolve(@context)
          {dependency: dependency, locked: locked, latest: latest} if locked != latest
        end
      end

      # Vendored dependencies whose files no longer match their locks.
      #
      # @return [Array<Hash>] +dependency+ and +problem+ (+:missing+,
      #   +:modified+ or +:unlocked+)
      def problems
        manifest = Manifest.for(@project)
        locks = manifest.locks.to_h { |lock| [lock.key, lock] }

        manifest.dependencies.filter_map do |dependency|
          lock = locks[dependency.key]
          checksum = Tree.checksum(game_path(dependency.destination))
          problem =
            if lock.nil? || lock.destination != dependency.destination then :unlocked
            elsif checksum.nil? then :missing
            elsif checksum != lock.checksum then :modified
            end
          {dependency: dependency, problem: problem} if problem
        end
      end

      private

      def check_update_names!(manifest, update)
        return unless update.is_a?(Array)

        unknown = update.reject { |name| manifest.find(name) }
        raise Error, "Unknown dependenc#{(unknown.size == 1) ? "y" : "ies"}: #{unknown.join(", ")}" if unknown.any?
      end

      def updating?(dependency, update)
        update == true || (update.is_a?(Array) && update.any? { |name| [dependency.name, dependency.key].include?(name) })
      end

      def install_dependency(dependency, lock, updating)
        reusable = lock && !updating && dependency.lockable? &&
          lock.ref == dependency.ref && lock.destination == dependency.destination
        target = game_path(dependency.destination)
        current = Tree.checksum(target)

        if reusable && current && current == lock.checksum
          return [lock, change(dependency, :unchanged, lock.commit)]
        end

        commit = reusable ? lock.commit : dependency.resolve(@context)
        managed = lock && lock.destination == dependency.destination

        staged_checksum = stage(dependency, commit) do |staged|
          checksum = Tree.checksum(staged)
          if current && current != checksum && (!managed || current != lock.checksum) && !@force
            raise ModifiedError, "#{relative(target)} has changes talon didn't make. " \
              "Move them aside, or pass --force to replace them with #{dependency.name}."
          end

          replace(target, staged) unless current == checksum
          checksum
        end

        remove_path(game_path(lock.destination)) if lock && lock.destination != dependency.destination

        new_lock = Lock.new(key: dependency.key, ref: dependency.ref, destination: dependency.destination,
          commit: commit, checksum: staged_checksum)
        action =
          if lock.nil? || current.nil? then :installed
          elsif lock.commit != commit then :updated
          elsif current == staged_checksum then :unchanged
          elsif dependency.lockable? then :restored
          else :updated
          end
        [new_lock, change(dependency, action, commit, lock&.commit)]
      end

      def remove(lock)
        target = game_path(lock.destination)
        current = Tree.checksum(target)
        if current && current != lock.checksum && !@force
          return Change.new(name: File.basename(lock.destination), action: :kept, dependency: nil, commit: nil, previous: nil)
        end

        remove_path(target)
        Change.new(name: File.basename(lock.destination), action: :removed, dependency: nil, commit: nil, previous: lock.commit)
      end

      def change(dependency, action, commit, previous = nil)
        Change.new(name: dependency.name, action: action, dependency: dependency, commit: commit, previous: previous)
      end

      # Fetches into a scratch directory on the project's filesystem and
      # yields the fetched path.
      def stage(dependency, commit)
        scratch = @project.path(".talon")
        FileUtils.mkdir_p(scratch)
        Dir.mktmpdir("deps-", scratch) do |dir|
          staged = File.join(dir, File.basename(dependency.destination))
          dependency.fetch(@context, commit, staged)
          yield staged
        end
      end

      def replace(target, staged)
        FileUtils.rm_rf(target)
        FileUtils.mkdir_p(File.dirname(target))
        File.rename(staged, target)
      end

      def remove_path(path)
        FileUtils.rm_rf(path)
        # Tidy up an emptied vendor/ (but never the game directory itself).
        dir = File.dirname(path)
        Dir.rmdir(dir) if dir != @project.game_dir && File.directory?(dir) && Dir.empty?(dir)
      end

      def game_path(relative)
        File.join(@project.game_dir, relative)
      end

      def relative(path)
        path.delete_prefix("#{@project.root}/")
      end
    end
  end
end
