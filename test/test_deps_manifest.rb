# frozen_string_literal: true

require "test_helper"

class TestDepsManifest < Minitest::Test
  Deps = DrTalon::Deps

  def setup
    @dir = File.realpath(Dir.mktmpdir)
    @path = File.join(@dir, "dependencies.rb")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def manifest(content)
    File.write(@path, content)
    Deps::Manifest.new(@path)
  end

  def test_missing_file_is_empty
    m = Deps::Manifest.new(@path)

    refute_predicate m, :exist?
    assert_empty m.dependencies
    assert_empty m.locks
  end

  def test_github_forms
    deps = manifest(<<~RUBY).dependencies
      github "asimmons91/talon", path: "lib", ref: "v1.0"
      github :pvande, :foodchain, "foodchain.rb", destination: "vendor/foodchain.rb"
      github "someone/whole-repo", as: "whole"
    RUBY

    assert_equal %w[talon foodchain.rb whole], deps.map(&:name)
    assert_equal %w[vendor/talon vendor/foodchain.rb vendor/whole], deps.map(&:destination)
    assert_equal ["github:asimmons91/talon/lib", "github:pvande/foodchain/foodchain.rb", "github:someone/whole-repo"],
      deps.map(&:key)
    assert_equal ["v1.0", nil, nil], deps.map(&:ref)
    assert_equal [1, 2, 3], deps.map(&:line)
  end

  def test_git_url_and_path_forms
    deps = manifest(<<~RUBY).dependencies
      git "https://codeberg.org/someone/tweens.git", path: "src", ref: "main"
      url "https://example.com/files/easing.rb"
      path "../my_lib/lib", as: "my_lib"
    RUBY

    assert_equal %w[tweens easing.rb my_lib], deps.map(&:name)
    assert_equal ["git:https://codeberg.org/someone/tweens.git?path=src", "https://example.com/files/easing.rb", "path:../my_lib/lib"],
      deps.map(&:key)
    refute deps.last.lockable?
  end

  def test_file_subpaths_are_named_after_the_file
    dep = manifest(%(github "o/r", path: "lib/tween.rb"\n)).dependencies.first

    assert_equal "tween.rb", dep.name
    assert_equal "vendor/tween.rb", dep.destination
  end

  def test_foodchain_require_is_ignored
    deps = manifest(%(require "vendor/foodchain"\n\ngithub :asimmons91, :talon, "lib", destination: "vendor/talon"\n)).dependencies

    assert_equal ["talon"], deps.map(&:name)
  end

  def test_destinations_must_be_inside_vendor
    ["app", "vendor", "vendor/../app", "/tmp/x", "lib/thing"].each do |destination|
      error = assert_raises(Deps::ManifestError) { manifest(%(url "https://x.test/a.rb", destination: "#{destination}"\n)) }
      assert_match(/dependencies\.rb:1: .*must be inside vendor/, error.message)
    end
  end

  def test_duplicate_names_report_both_lines
    error = assert_raises(Deps::ManifestError) do
      manifest(%(github "a/talon"\ngithub "b/talon"\n))
    end

    assert_match(/dependencies\.rb:2: talon has the same name as talon \(line 1\)/, error.message)
  end

  def test_errors_point_at_the_line
    error = assert_raises(Deps::ManifestError) { manifest(%(github "a/b"\n\nbogus "x"\n)) }

    assert_match(/dependencies\.rb:3: /, error.message)
  end

  def test_syntax_errors_are_manifest_errors
    assert_raises(Deps::ManifestError) { manifest(%(github "a/b", path: \n)) }
  end

  def test_write_locks_keeps_the_config_verbatim
    config = %(# my deps\ngithub "a/b", ref: "v1"   # pinned\n)
    m = manifest(config)
    lock = Deps::Lock.new(key: "github:a/b", ref: "v1", destination: "vendor/b", commit: "c" * 40, checksum: "sha256:abc")

    m.write_locks([lock])

    content = File.read(@path)
    assert content.start_with?(config.rstrip + "\n\n__END__\n")
    assert_includes content, "github:a/b\tv1\tvendor/b\t#{"c" * 40}\tsha256:abc\n"
    assert_equal [lock], Deps::Manifest.new(@path).locks
  end

  def test_missing_fields_are_dashes
    lock = Deps::Lock.new(key: "path:../x", ref: nil, destination: "vendor/x", commit: nil, checksum: "sha256:1")

    assert_equal "path:../x\t-\tvendor/x\t-\tsha256:1", lock.to_line
    assert_equal lock, Deps::Lock.parse(lock.to_line)
  end

  def test_foodchain_etag_locks_are_flagged_and_dropped
    m = manifest(%(github :a, :b, "lib"\n__END__\n# comment\ngithub:a/b/lib\tW/"etag"\n))

    assert m.foodchain_locks
    assert_empty m.locks
  end

  def test_add_appends_before_end
    m = manifest(%(github "a/b"\n\n__END__\n\n# header\n))

    m.add(%(url "https://x.test/c.rb"))

    assert_equal %w[b c.rb], Deps::Manifest.new(@path).dependencies.map(&:name)
    assert File.read(@path).index("c.rb") < File.read(@path).index("__END__")
  end

  def test_add_to_a_new_file
    Deps::Manifest.new(@path).add(%(github "a/b"))

    assert_equal ["b"], Deps::Manifest.new(@path).dependencies.map(&:name)
  end

  def test_invalid_additions_leave_the_file_alone
    original = %(github "a/b"\n)
    m = manifest(original)

    assert_raises(Deps::ManifestError) { m.add(%(github "c/b")) }
    assert_equal original, File.read(@path)
  end

  def test_remove_deletes_the_declaring_line
    m = manifest(%(# keep me\ngithub "a/b"\nurl "https://x.test/c.rb"\n))

    m.remove(m.find("b"))

    assert File.read(@path).start_with?(%(# keep me\nurl "https://x.test/c.rb"\n\n__END__\n))
    assert_equal ["c.rb"], Deps::Manifest.new(@path).dependencies.map(&:name)
  end

  def test_remove_refuses_multi_line_declarations
    m = manifest(%(github "a/b",\n  ref: "v1"\n))

    assert_raises(Deps::ManifestError) { m.remove(m.find("b")) }
  end

  def test_find_by_name_or_key
    m = manifest(%(github "a/b", path: "lib"\n))

    assert_equal "b", m.find("b").name
    assert_equal "b", m.find("github:a/b/lib").name
    assert_nil m.find("nope")
  end
end
