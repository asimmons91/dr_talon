# frozen_string_literal: true

require "rbconfig"

module DrTalon
  # Copies single files, cloning them (reflinks) where the filesystem allows so
  # copies of the same engine into many projects share storage. Falls back to
  # a byte copy across filesystems or on filesystems without cloning.
  module FileCopy
    # Linux +ioctl(dst, FICLONE, src)+; supported by btrfs and XFS.
    FICLONE = 0x40049409
    CLONE_UNSUPPORTED = [
      Errno::EOPNOTSUPP, Errno::EXDEV, Errno::EINVAL, Errno::ENOTTY, Errno::EPERM, Errno::EBADF, NotImplementedError
    ].freeze

    module_function

    # Copies +src+ to +dst+, keeping the mode and timestamps. An existing
    # +dst+ (including a symlink) is replaced rather than written through.
    #
    # @param src [String]
    # @param dst [String]
    # @return [Boolean] whether the file was cloned rather than byte-copied
    def copy(src, dst)
      File.unlink(dst) if File.symlink?(dst) || File.exist?(dst)

      cloned = File.open(src, "rb") do |input|
        File.open(dst, File::WRONLY | File::CREAT | File::EXCL | File::BINARY) do |output|
          try_clone(input, output).tap { |done| IO.copy_stream(input, output) unless done }
        end
      end

      stat = File.stat(src)
      File.chmod(stat.mode & 0o7777, dst)
      File.utime(stat.atime, stat.mtime, dst)
      cloned
    end

    # @return [Boolean] whether the clone succeeded
    def try_clone(input, output)
      return false unless RbConfig::CONFIG["host_os"].include?("linux")

      output.ioctl(FICLONE, input.fileno)
      true
    rescue *CLONE_UNSUPPORTED
      false
    end
  end
end
