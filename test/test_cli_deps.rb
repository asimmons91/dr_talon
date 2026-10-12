# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class TestCLIDeps < Minitest::Test
  include EngineFixtures
  include DepsFixtures

  def setup
    @dir = File.realpath(Dir.mktmpdir)
    @previous_home = ENV["DR_TALON_HOME"]
    ENV["DR_TALON_HOME"] = File.join(@dir, "home")
    @remotes = File.join(@dir, "remotes")
    @v1 = commit_to(@remotes, "asimmons91", "talon", {"lib/talon.rb" => "v1", "lib/talon/version.rb" => "1"})
    @context = deps_context(@remotes)
    @root = build_project(@dir)
  end

  def teardown
    ENV["DR_TALON_HOME"] = @previous_home
    FileUtils.rm_rf(@dir)
  end

  def talon(*args)
    DrTalon::Deps::Context.stub(:default, @context) do
      Dir.chdir(@root) { capture_io { DrTalon::CLI.start(args) } }
    end
  end

  def manifest_text
    File.read(File.join(@root, "mygame", "dependencies.rb"))
  end

  def test_add_declares_installs_and_prints_the_require_line
    out, _err = talon("add", "github:asimmons91/talon", "--path", "lib")

    assert_match(%r{add\s+mygame/dependencies\.rb: github "asimmons91/talon", path: "lib"}, out)
    assert_match(/install\s+talon \(github:asimmons91\/talon\/lib @ #{@v1[0, 7]}\)/, out)
    assert_match(%r{require "vendor/talon/talon\.rb"}, out)
    assert_equal "v1", File.read(File.join(@root, "mygame", "vendor", "talon", "talon.rb"))
    assert_includes manifest_text, "github:asimmons91/talon/lib\t-\tvendor/talon\t#{@v1}"
  end

  def test_add_with_ref_and_name
    commit_to(@remotes, "asimmons91", "talon", {"lib/talon.rb" => "v2"})

    talon("add", "github:asimmons91/talon", "--path", "lib", "--ref", @v1, "--as", "framework")

    assert_includes manifest_text, %(github "asimmons91/talon", path: "lib", ref: "#{@v1}", as: "framework")
    assert_equal "v1", File.read(File.join(@root, "mygame", "vendor", "framework", "talon.rb"))
  end

  def test_failed_add_restores_the_manifest
    talon("add", "github:asimmons91/talon", "--path", "lib")
    before = manifest_text

    assert_raises(SystemExit) { talon("add", "github:asimmons91/talon", "--ref", "nope", "--as", "other") }
    assert_equal before, manifest_text

    assert_raises(SystemExit) { talon("add", "github:nobody/missing") }
    assert_equal before, manifest_text
  end

  def test_failed_first_add_leaves_no_manifest
    assert_raises(SystemExit) { talon("add", "github:nobody/missing") }

    refute File.exist?(File.join(@root, "mygame", "dependencies.rb"))
  end

  def test_add_rejects_bad_sources
    assert_raises(SystemExit) { talon("add", "asimmons91/talon") }
    assert_raises(SystemExit) { talon("add", "github:not-a-repo") }
  end

  def test_remove_deletes_declaration_lock_and_files
    talon("add", "github:asimmons91/talon", "--path", "lib")

    out, _err = talon("remove", "talon")

    assert_match(/remove\s+talon/, out)
    refute_includes manifest_text, "asimmons91"
    refute File.exist?(File.join(@root, "mygame", "vendor", "talon"))
    assert_raises(SystemExit) { talon("remove", "talon") }
  end

  def test_install_update_and_outdated
    talon("add", "github:asimmons91/talon", "--path", "lib")

    out, _err = talon("install")
    assert_match(/using\s+talon/, out)

    out, _err = talon("outdated")
    assert_match(/All dependencies are up to date/, out)

    v2 = commit_to(@remotes, "asimmons91", "talon", {"lib/talon.rb" => "v2"})
    out, _err = talon("outdated")
    assert_match(/talon\s+#{@v1[0, 7]}\s+#{v2[0, 7]}\s+default branch/, out)

    out, _err = talon("update")
    assert_match(/update\s+talon #{@v1[0, 7]} → #{v2[0, 7]}/, out)
  end

  def test_install_without_a_manifest
    out, _err = talon("install")

    assert_match(/No dependencies\.rb in mygame\/; add a dependency with `talon add`/, out)
  end

  def test_install_reports_local_edits
    talon("add", "github:asimmons91/talon", "--path", "lib")
    File.write(File.join(@root, "mygame", "vendor", "talon", "talon.rb"), "hacked")

    assert_raises(SystemExit) { talon("install") }

    out, _err = talon("install", "--force")
    assert_match(/restore\s+talon .*local changes replaced/, out)
  end

  def test_install_restores_the_pinned_engine_first
    capture_io { DrTalon::CLI.start(["engine", "import", build_engine_zip(@dir)]) }
    File.write(File.join(@root, ".dragonruby-version"), "7.23-pro\n")

    out, _err = talon("install")

    assert_match(/Installed engine 7\.23-pro-linux-amd64/, out)
    assert File.executable?(File.join(@root, "dragonruby"))

    out, _err = talon("install")
    refute_match(/Installed engine/, out)
  end

  def test_install_mentions_dropped_foodchain_locks
    File.write(File.join(@root, "mygame", "dependencies.rb"),
      %(require "vendor/foodchain"\ngithub :asimmons91, :talon, "lib", destination: "vendor/talon"\n__END__\ngithub:asimmons91/talon/lib\tW/"x"\n))

    out, _err = talon("install")

    assert_match(/Foodchain's ETag locks/, out)
    assert_includes manifest_text, "github:asimmons91/talon/lib\t-\tvendor/talon\t#{@v1}"
  end

  def test_doctor_reports_dependencies
    talon("add", "github:asimmons91/talon", "--path", "lib")
    project = DrTalon::Project.new(@root)
    store = DrTalon::Engine::Store.new(File.join(@dir, "engines"))
    messages = -> { DrTalon::Doctor.new(project, store).checks.map { |check| [check.status, check.message] } }

    assert_includes messages.call, [:ok, "1 dependency installed"]

    File.write(File.join(@root, "mygame", "vendor", "talon", "talon.rb"), "hacked")
    assert_includes messages.call, [:warning, "vendor/talon has local changes; `talon install --force` restores it"]

    FileUtils.rm_rf(File.join(@root, "mygame", "vendor", "talon"))
    assert_includes messages.call, [:error, "talon is locked but vendor/talon is missing. Run `talon install`."]
  end
end
