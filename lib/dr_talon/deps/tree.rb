# frozen_string_literal: true

require "digest"
require "fileutils"
require "rubygems/package"
require "stringio"
require "zlib"

module DrTalon
  module Deps
    # File tree helpers: checksums of vendored files, copying a subpath out of
    # a source tree, and unpacking tarballs.
    module Tree
      module_function

      # A digest of a file or directory's contents and executable bits, so
      # local edits to vendored files can be detected.
      #
      # @param path [String]
      # @return [String, nil] "sha256:<hex>", or nil if +path+ doesn't exist
      def checksum(path)
        return nil unless File.exist?(path)
        return "sha256:#{Digest::SHA256.file(path).hexdigest}" if File.file?(path)

        digest = Digest::SHA256.new
        Dir.glob("**/*", File::FNM_DOTMATCH, base: path).sort.each do |relative|
          full = File.join(path, relative)
          next unless File.file?(full)

          digest << relative << "\0" << (File.executable?(full) ? "x" : "-") << Digest::SHA256.file(full).hexdigest << "\n"
        end
        "sha256:#{digest.hexdigest}"
      end

      # Copies +subpath+ of +root+ (a file or directory, or all of +root+ when
      # empty) to +target+, skipping .git and symlinks.
      #
      # @return [void]
      # @raise [FetchError] if +subpath+ doesn't exist
      def copy_subpath(root, subpath, target)
        source = subpath.to_s.empty? ? root : File.join(root, subpath)
        raise FetchError, "#{subpath} doesn't exist in the dependency." unless File.exist?(source)

        if File.file?(source)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(source, target, preserve: true)
          return
        end

        Dir.glob("**/*", File::FNM_DOTMATCH, base: source).sort.each do |relative|
          next if relative.split("/").include?(".git") || File.basename(relative).match?(/\A\.\.?\z/)

          from = File.join(source, relative)
          to = File.join(target, relative)
          if File.symlink?(from)
            next
          elsif File.directory?(from)
            FileUtils.mkdir_p(to)
          else
            FileUtils.mkdir_p(File.dirname(to))
            FileUtils.cp(from, to, preserve: true)
          end
        end
        FileUtils.mkdir_p(target)
      end

      # Unpacks a .tar.gz into +dir+, dropping the single top-level directory
      # GitHub wraps archives in. Skips links and anything that would land
      # outside +dir+.
      #
      # @param data [String] gzipped tar bytes
      # @param dir [String]
      # @return [void]
      def untar(data, dir, strip: 1)
        Zlib::GzipReader.wrap(StringIO.new(data)) do |gzip|
          Gem::Package::TarReader.new(gzip) do |tar|
            tar.each do |entry|
              parts = entry.full_name.split("/").reject(&:empty?).drop(strip)
              next if parts.empty? || parts.include?("..")

              target = File.join(dir, *parts)
              if entry.directory?
                FileUtils.mkdir_p(target)
              elsif entry.file?
                FileUtils.mkdir_p(File.dirname(target))
                File.binwrite(target, entry.read.to_s)
                File.chmod(entry.header.mode & 0o755 | 0o600, target)
              end
            end
          end
        end
      rescue Zlib::Error, Gem::Package::TarInvalidError => e
        raise FetchError, "Couldn't unpack the archive: #{e.message}"
      end
    end
  end
end
