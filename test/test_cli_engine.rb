# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestCLIEngine < Minitest::Test
  include EngineFixtures

  def setup
    @dir = Dir.mktmpdir
    @previous_home = ENV["DR_TALON_HOME"]
    ENV["DR_TALON_HOME"] = File.join(@dir, "home")
  end

  def teardown
    ENV["DR_TALON_HOME"] = @previous_home
    FileUtils.rm_rf(@dir)
  end

  def talon(*args)
    capture_io { DrTalon::CLI.start(args) }
  end

  def engines_dir
    DrTalon::Paths.new.engines_dir
  end

  def test_list_when_empty
    out, _err = talon("engine", "list")

    assert_match(/No engines cached yet/, out)
  end

  def test_import_list_and_which
    out, _err = talon("engine", "import", build_engine_zip(@dir))
    assert_match(/Imported 7\.23-pro-linux-amd64/, out)

    out, _err = talon("engine", "list")
    assert_match(/^\s+ID\s+VERSION\s+TIER\s+PLATFORM\s+BUILT$/, out)
    assert_match(/^\s+7\.23-pro-linux-amd64\s+7\.23\s+pro\s+linux-amd64\s+2026-10-07$/, out)

    out, _err = talon("engine", "which", "7.23")
    assert_equal "#{File.join(engines_dir, "7.23-pro-linux-amd64")}\n", out
  end

  def test_reimporting_the_same_zip_reports_no_change
    zip = build_engine_zip(@dir)
    talon("engine", "import", zip)

    out, _err = talon("engine", "import", zip)

    assert_match(/already cached from the same zip/, out)
  end

  def test_import_errors_exit_non_zero
    assert_raises(SystemExit) { talon("engine", "import", File.join(@dir, "missing.zip")) }
    assert_raises(SystemExit) { talon("engine", "import", build_engine_zip(@dir), "--tier", "gold") }
  end

  def test_which_unknown_engine_exits_non_zero
    assert_raises(SystemExit) { talon("engine", "which", "7.23") }
  end

  def test_uninstall_asks_first
    talon("engine", "import", build_engine_zip(@dir))
    stdin = $stdin
    $stdin = StringIO.new("n\n")

    out, _err = talon("engine", "uninstall", "7.23")

    assert_match(/Kept 7\.23-pro-linux-amd64/, out)
    assert File.directory?(File.join(engines_dir, "7.23-pro-linux-amd64"))
  ensure
    $stdin = stdin
  end

  def test_uninstall_with_yes
    talon("engine", "import", build_engine_zip(@dir))

    out, _err = talon("engine", "uninstall", "--yes", "7.23")

    assert_match(/Removed 7\.23-pro-linux-amd64/, out)
    refute File.exist?(File.join(engines_dir, "7.23-pro-linux-amd64"))
  end

  def in_project(layout: :full, &block)
    root = build_project(@dir, layout: layout)
    Dir.chdir(root) { block.call(root) }
  end

  def test_use_installs_and_pins
    talon("engine", "import", build_engine_zip(@dir))

    in_project do |root|
      out, _err = talon("engine", "use", "7.23")

      assert_match(/Installed 7\.23-pro-linux-amd64 into .* \(4 files/, out)
      assert_match(/Pinned 7\.23-pro in \.dragonruby-version/, out)
      assert_equal "7.23-pro\n", File.read(File.join(root, ".dragonruby-version"))
      assert File.executable?(File.join(root, "dragonruby"))
    end
  end

  def test_use_without_an_engine_installs_the_pin
    talon("engine", "import", build_engine_zip(@dir))

    in_project do |root|
      File.write(File.join(root, ".dragonruby-version"), "7.23-pro\n")

      out, _err = talon("engine", "use")

      assert_match(/Installed 7\.23-pro-linux-amd64/, out)
      refute_match(/Pinned/, out)

      out, _err = talon("engine", "use")
      assert_match(/Reinstalled 7\.23-pro-linux-amd64/, out)
    end
  end

  def test_use_reports_the_engine_it_replaced
    talon("engine", "import", build_engine_zip(@dir))
    talon("engine", "import", build_engine_zip(@dir, name: "dragonruby-pro-linux-amd64-7.24.zip", version: "7.24"))

    in_project do
      talon("engine", "use", "7.23")
      out, _err = talon("engine", "use", "7.24")

      assert_match(/replaced 7\.23-pro-linux-amd64/, out)
      assert_match(/Pinned 7\.24-pro/, out)
    end
  end

  def test_use_without_engine_or_pin_fails
    in_project do
      assert_raises(SystemExit) { talon("engine", "use") }
    end
  end

  def test_use_refuses_other_platforms
    talon("engine", "import", build_engine_zip(@dir))

    in_project do
      assert_raises(SystemExit) { talon("engine", "use", "7.23-pro-other-platform") }
    end
  end

  def test_use_outside_a_project_fails
    talon("engine", "import", build_engine_zip(@dir))

    Dir.chdir(@dir) do
      assert_raises(SystemExit) { talon("engine", "use", "7.23") }
    end
  end

  def test_current_and_which_follow_the_project
    talon("engine", "import", build_engine_zip(@dir))

    in_project do
      out, _err = talon("engine", "current")
      assert_match(/Pinned:\s+nothing/, out)

      talon("engine", "use", "7.23")

      out, _err = talon("engine", "current")
      assert_match(/Pinned:\s+7\.23-pro$/, out)
      assert_match(/Installed:\s+7\.23-pro-linux-amd64$/, out)

      out, _err = talon("engine", "which")
      assert_equal "#{File.join(engines_dir, "7.23-pro-linux-amd64")}\n", out

      out, _err = talon("engine", "list")
      assert_match(/^\*\s+7\.23-pro-linux-amd64/, out)
    end
  end

  def test_doctor_passes_for_a_healthy_project
    talon("engine", "import", build_engine_zip(@dir))

    in_project(layout: :game_only) do
      talon("engine", "use", "7.23")

      out, _err = talon("doctor")

      assert_match(/✓ Game found in the project root \(game-only layout\)/, out)
      assert_match(/✓ 7\.23-pro-linux-amd64 is installed/, out)
    end
  end

  def test_doctor_exits_non_zero_on_problems
    in_project do
      assert_raises(SystemExit) { talon("doctor") }
    end
  end
end
