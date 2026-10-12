# frozen_string_literal: true

require "test_helper"

class TestDepsTree < Minitest::Test
  Tree = DrTalon::Deps::Tree

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write(relative, content = "x")
    path = File.join(@dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def test_checksum_tracks_content_names_and_exec_bits
    write("lib/a.rb", "a")
    root = File.join(@dir, "lib")
    first = Tree.checksum(root)

    assert_equal first, Tree.checksum(root)
    write("lib/a.rb", "changed")
    refute_equal first, (second = Tree.checksum(root))
    File.chmod(0o755, File.join(root, "a.rb"))
    refute_equal second, Tree.checksum(root)
    assert_nil Tree.checksum(File.join(@dir, "missing"))
    assert Tree.checksum(write("one.rb")).start_with?("sha256:")
  end

  def test_copy_subpath_directory_skips_git_and_symlinks
    write("repo/lib/a.rb")
    write("repo/lib/nested/b.rb")
    write("repo/lib/.git/config")
    File.symlink("/etc/passwd", File.join(@dir, "repo", "lib", "link"))

    Tree.copy_subpath(File.join(@dir, "repo"), "lib", File.join(@dir, "out"))

    listing = Dir.glob("**/*", File::FNM_DOTMATCH, base: File.join(@dir, "out")).reject { |p| p == "." }.sort
    assert_equal %w[a.rb nested nested/b.rb], listing
  end

  def test_copy_subpath_file_and_missing
    write("repo/lib/tween.rb", "tween")

    Tree.copy_subpath(File.join(@dir, "repo"), "lib/tween.rb", File.join(@dir, "vendor", "tween.rb"))

    assert_equal "tween", File.read(File.join(@dir, "vendor", "tween.rb"))
    assert_raises(DrTalon::Deps::FetchError) { Tree.copy_subpath(File.join(@dir, "repo"), "nope", File.join(@dir, "x")) }
  end

  def test_untar_strips_the_top_directory_and_skips_escapes
    data = tarball(
      "repo-sha/" => nil, "repo-sha/lib/a.rb" => "a", "repo-sha/../../escape.rb" => "bad", "repo-sha/run" => ["#!/bin/sh", 0o755]
    )

    Tree.untar(data, File.join(@dir, "out"))

    assert_equal "a", File.read(File.join(@dir, "out", "lib", "a.rb"))
    assert File.executable?(File.join(@dir, "out", "run"))
    refute File.exist?(File.join(@dir, "escape.rb"))
    refute File.exist?(File.join(File.dirname(@dir), "escape.rb"))
  end

  def test_untar_rejects_garbage
    assert_raises(DrTalon::Deps::FetchError) { Tree.untar("not a tarball", @dir) }
  end

  private

  def tarball(entries)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) do |gzip|
      Gem::Package::TarWriter.new(gzip) do |tar|
        entries.each do |name, (content, mode)|
          if content.nil?
            tar.mkdir(name, 0o755)
          else
            tar.add_file_simple(name, mode || 0o644, content.bytesize) { |f| f.write(content) }
          end
        end
      end
    end
    io.string
  end
end
