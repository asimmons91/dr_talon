# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class TestFileCopy < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @src = File.join(@dir, "src")
    File.write(@src, "engine bytes")
    File.chmod(0o755, @src)
    File.utime(Time.at(1_000_000), Time.at(1_000_000), @src)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_copies_contents_mode_and_mtime
    dst = File.join(@dir, "dst")

    DrTalon::FileCopy.copy(@src, dst)

    assert_equal "engine bytes", File.read(dst)
    assert_equal 0o755, File.stat(dst).mode & 0o777
    assert_equal Time.at(1_000_000), File.mtime(dst)
  end

  def test_replaces_a_symlink_instead_of_writing_through_it
    outside = File.join(@dir, "outside")
    File.write(outside, "keep me")
    dst = File.join(@dir, "dst")
    File.symlink(outside, dst)

    DrTalon::FileCopy.copy(@src, dst)

    refute File.symlink?(dst)
    assert_equal "engine bytes", File.read(dst)
    assert_equal "keep me", File.read(outside)
  end

  def test_falls_back_to_a_byte_copy_when_cloning_is_unsupported
    dst = File.join(@dir, "dst")

    DrTalon::FileCopy.stub(:try_clone, false) do
      refute DrTalon::FileCopy.copy(@src, dst)
    end
    assert_equal "engine bytes", File.read(dst)
  end
end
