# frozen_string_literal: true

require "digest"
require "fileutils"
require "time"
require "zip"

module DrTalon
  module Engine
    # Adds a DragonRuby distribution to the {Store}, from either the zip as
    # downloaded or a directory it was already extracted to.
    class Importer
      # @!attribute [r] installation
      #   @return [Installation]
      # @!attribute [r] status
      #   @return [Symbol] +:installed+, +:replaced+ or +:unchanged+ (the same
      #     zip was already imported)
      Result = Data.define(:installation, :status)

      # @param store [Store]
      # @param tier [String, nil] overrides tier detection
      # @param platform [String, nil] overrides platform detection
      # @param force [Boolean] replace an already cached engine with the same id
      def initialize(store, tier: nil, platform: nil, force: false)
        @store = store
        @tier = tier
        @platform = platform
        @force = force
      end

      # @param source [String] path to a .zip or an extracted engine directory
      # @return [Result]
      # @raise [Error] if the source is missing or isn't a DragonRuby engine
      # @raise [AlreadyInstalled] if the id is taken and +force+ is off
      def import(source)
        source = File.expand_path(source)

        @store.stage do |staging|
          root, hints, sha256 =
            if File.directory?(source)
              copy_directory(source, staging)
            elsif File.file?(source)
              extract_zip(source, staging)
            else
              raise Error, "#{source} does not exist."
            end

          details = Inspector.new(root, hints: hints, tier: @tier, platform: @platform).details
          installation = Installation.new(
            **details,
            path: @store.path_for("#{details[:version]}-#{details[:tier]}-#{details[:platform]}"),
            sha256: sha256,
            source: File.basename(source),
            imported_at: Time.now.utc.iso8601
          )

          install(installation, root)
        end
      end

      private

      def copy_directory(source, staging)
        root = Inspector.find_root(source)
        FileUtils.cp_r(root, staging, preserve: true)

        hints = [File.basename(source), File.basename(File.dirname(root))]
        [File.join(staging, File.basename(root)), hints, nil]
      end

      def extract_zip(source, staging)
        Zip::File.open(source, restore_permissions: true) { |zip| zip.extract_all(staging) }

        [Inspector.find_root(staging), [File.basename(source, ".*")], Digest::SHA256.file(source).hexdigest]
      rescue Zip::Error => e
        raise Error, "Can't read #{source} as a zip: #{e.message}"
      end

      def install(installation, root)
        status = :installed

        if (existing = @store.get(installation.id))
          if !@force && existing.sha256 && existing.sha256 == installation.sha256
            return Result.new(installation: existing, status: :unchanged)
          end

          unless @force
            raise AlreadyInstalled, "#{installation.id} is already cached (imported from #{existing.source}). " \
              "Pass --force to replace it."
          end

          @store.remove(existing)
          status = :replaced
        end

        installation.write_metadata(root)
        File.rename(root, installation.path)

        Result.new(installation: installation, status: status)
      end
    end
  end
end
