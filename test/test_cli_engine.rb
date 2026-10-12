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
    assert_match(/^ID\s+VERSION\s+TIER\s+PLATFORM\s+BUILT$/, out)
    assert_match(/^7\.23-pro-linux-amd64\s+7\.23\s+pro\s+linux-amd64\s+2026-10-07$/, out)

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
end
