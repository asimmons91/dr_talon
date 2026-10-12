# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class TestCLIWorkflow < Minitest::Test
  include EngineFixtures

  def setup
    @dir = File.realpath(Dir.mktmpdir)
    @previous_home = ENV["DR_TALON_HOME"]
    ENV["DR_TALON_HOME"] = File.join(@dir, "home")
  end

  def teardown
    ENV["DR_TALON_HOME"] = @previous_home
    FileUtils.rm_rf(@dir)
  end

  def in_project(layout: :full, binaries: %w[dragonruby dragonruby-publish dragonruby-httpd], &block)
    @root = build_project(@dir, layout: layout)
    binaries.each do |name|
      File.write(File.join(@root, name), "")
      File.chmod(0o755, File.join(@root, name))
    end
    Dir.chdir(@root, &block)
  end

  def talon(*args)
    capture_io { DrTalon::CLI.start(args) }
  end

  # Runs a command and returns what it would have exec'd.
  def exec_of(*args)
    calls = []
    DrTalon::Runner.stub(:exec_process, ->(argv, chdir:) { calls << [argv, chdir] }) do
      @out, @err = talon(*args)
    end
    assert_equal 1, calls.size, "expected one exec"
    calls.first
  end

  def write(*relative, content:)
    path = File.join(@root, *relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def test_run_passes_arguments_through
    in_project do
      argv, chdir = exec_of("run", "--record", "--speed", "4")

      assert_equal [File.join(@root, "dragonruby"), "mygame", "--record", "--speed", "4"], argv
      assert_equal @root, chdir
    end
  end

  def test_run_without_an_engine_fails
    in_project(binaries: []) do
      assert_raises(SystemExit) { talon("run") }
    end
  end

  def test_build_packages_and_warns_about_metadata
    in_project do
      write("mygame", "metadata", "game_metadata.txt", content: STOCK_METADATA)

      argv, _chdir = exec_of("build")

      assert_equal [File.join(@root, "dragonruby-publish"), "--only-package", "mygame"], argv
      assert_match(/doesn't set devid, devtitle, gameid, gametitle/, @out)
    end
  end

  def test_build_in_a_game_only_project_explains_the_layout
    in_project(layout: :game_only, binaries: %w[dragonruby]) do
      assert_raises(SystemExit) { talon("build") }
    end
  end

  def test_serve_defaults_to_the_newest_html5_build
    in_project do
      write("builds", "game-html5-0.1", "index.html", content: "")

      argv, _chdir = exec_of("serve", "--port", "9000")

      assert_equal [File.join(@root, "dragonruby-httpd"), "builds/game-html5-0.1", "9000"], argv
      assert_match(%r{http://localhost:9000/}, @out)
    end
  end

  def test_serve_without_a_build_fails
    in_project do
      assert_raises(SystemExit) { talon("serve") }
    end
  end

  def test_clean
    in_project do
      write("logs", "x.log", content: "")

      out, _err = talon("clean")
      assert_match(/remove\s+logs/, out)
      refute File.exist?(File.join(@root, "logs"))

      out, _err = talon("clean")
      assert_match(/Nothing to clean/, out)
    end
  end

  def test_test_reports_each_file_and_passes
    in_project(layout: :game_only, binaries: []) do
      install_fake_dragonruby(@root)
      write("test", "a_tests.rb", content: "")
      write("test", "a_tests.out", content: dragonruby_output("passed"))

      out, _err = talon("test")

      assert_match(%r{✓ test/a_tests\.rb \(1 passed\)}, out)
      assert_match(/1 file, 1 test passed/, out)
    end
  end

  def test_test_exits_non_zero_and_shows_failures
    in_project(layout: :game_only, binaries: []) do
      install_fake_dragonruby(@root)
      write("test", "a_tests.rb", content: "")
      write("test", "a_tests.out", content: dragonruby_output("passed"))
      write("test", "b_tests.rb", content: "")
      write("test", "b_tests.out", content: dragonruby_output("failed"))

      error = assert_raises(SystemExit) { capture_io { DrTalon::CLI.start(["test"]) } }

      assert_equal 1, error.status
    end
  end

  def test_test_failure_details_are_printed
    in_project(layout: :game_only, binaries: []) do
      install_fake_dragonruby(@root)
      write("test", "b_tests.rb", content: "")
      write("test", "b_tests.out", content: dragonruby_output("failed"))

      out, = capture_io do
        assert_raises(SystemExit) { DrTalon::CLI.start(["test", "test/b_tests.rb"]) }
      end

      assert_match(%r{✗ test/b_tests\.rb \(1 passed, 1 failed\)}, out)
      assert_match(/one is not two/, out)
      assert_match(/1 failed, 1 file with problems/, out)
    end
  end

  def test_test_without_test_files_fails
    in_project(layout: :game_only, binaries: []) do
      install_fake_dragonruby(@root)

      assert_raises(SystemExit) { talon("test") }
    end
  end
end
