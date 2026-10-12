# frozen_string_literal: true

require "test_helper"

class TestRunner < Minitest::Test
  include EngineFixtures

  def setup
    @dir = File.realpath(Dir.mktmpdir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def project(layout: :full)
    @root = build_project(@dir, layout: layout)
    @project = DrTalon::Project.new(@root)
    DrTalon::Runner.new(@project)
  end

  def touch(*relative, content: "")
    path = File.join(@root, *relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def test_commands_for_the_full_layout
    runner = project
    %w[dragonruby dragonruby-publish dragonruby-httpd].each { |name| touch(name) }

    assert_equal [File.join(@root, "dragonruby"), "mygame", "--record"], runner.run_command(["--record"])
    assert_equal [File.join(@root, "dragonruby-publish"), "--only-package", "mygame"], runner.build_command
    assert_equal [File.join(@root, "dragonruby-httpd"), "builds/x", "8080"], runner.serve_command("builds/x", 8080)
    assert_equal [File.join(@root, "dragonruby"), "mygame", "--test", "tests/a_tests.rb"], runner.test_command("tests/a_tests.rb")
  end

  def test_game_only_layout_runs_the_root
    runner = project(layout: :game_only)
    touch("dragonruby")

    assert_equal [File.join(@root, "dragonruby"), "."], runner.run_command
  end

  def test_windows_binaries_are_found
    runner = project
    touch("dragonruby.exe")

    assert_equal File.join(@root, "dragonruby.exe"), runner.binary
  end

  def test_missing_binaries_explain_what_to_do
    error = assert_raises(DrTalon::Runner::MissingBinary) { project.binary }
    assert_match(/talon engine use/, error.message)

    error = assert_raises(DrTalon::Runner::MissingBinary) { project(layout: :game_only).binary("dragonruby-publish") }
    assert_match(/full layout/, error.message)
  end

  def test_test_files_default_to_test_and_tests_dirs
    runner = project
    touch("mygame", "tests", "a_tests.rb")
    touch("mygame", "test", "nested", "b_tests.rb")
    touch("mygame", "tests", "helper.rb")
    touch("mygame", "app", "c_tests.rb")

    assert_equal %w[test/nested/b_tests.rb tests/a_tests.rb], runner.test_files
  end

  def test_test_files_from_arguments
    runner = project(layout: :game_only)
    touch("test", "a_tests.rb")
    touch("test", "unit", "b_tests.rb")
    touch("test", "helper.rb")

    assert_equal ["test/a_tests.rb"], runner.test_files(["test/a_tests.rb"], base: @root)
    assert_equal ["test/unit/b_tests.rb"], runner.test_files(["unit"], base: File.join(@root, "test"))
    assert_equal %w[test/a_tests.rb test/unit/b_tests.rb], runner.test_files(["."], base: @root)
    assert_equal ["test/helper.rb"], runner.test_files(["test/helper.rb"], base: @root), "explicit files run as given"
  end

  def test_test_files_must_exist_inside_the_game
    runner = project

    assert_raises(DrTalon::Error) { runner.test_files(["mygame/tests/missing_tests.rb"], base: @root) }
    assert_raises(DrTalon::Error) { runner.test_files([@dir], base: @root) }
  end

  def test_run_test_parses_the_output
    runner = project
    install_fake_dragonruby(@root)
    touch("mygame", "tests", "a_tests.out", content: dragonruby_output("failed"))

    report = runner.run_test("tests/a_tests.rb")

    assert_equal :failed, report.status
    assert_equal "mygame --test tests/a_tests.rb SDL_VIDEO_DRIVER=dummy\n", File.read(File.join(@root, "args.log"))
  end

  def test_run_test_with_a_window
    runner = project
    install_fake_dragonruby(@root)
    touch("mygame", "tests", "a_tests.out", content: dragonruby_output("passed"))

    previous = ENV.delete("SDL_VIDEO_DRIVER")
    assert_equal :passed, runner.run_test("tests/a_tests.rb", headless: false).status
    assert_equal "mygame --test tests/a_tests.rb SDL_VIDEO_DRIVER=\n", File.read(File.join(@root, "args.log"))
  ensure
    ENV["SDL_VIDEO_DRIVER"] = previous if previous
  end

  def test_run_test_times_out
    runner = project
    install_fake_dragonruby(@root)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    report = runner.run_test("tests/sleep_tests.rb", timeout: 0.3)

    assert_equal :timeout, report.status
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 4
  end

  def test_html5_build_picks_the_newest_with_an_index
    runner = project
    assert_nil runner.html5_build

    touch("builds", "game-html5-0.1", "index.html")
    touch("builds", "game-html5-0.2", "index.html")
    touch("builds", "game-html5-broken", "readme.txt")
    File.utime(Time.now - 60, Time.now - 60, File.join(@root, "builds", "game-html5-0.1"))

    assert_equal "builds/game-html5-0.2", runner.html5_build
  end

  def test_clean_removes_generated_directories_only
    runner = project
    %w[builds logs tmp errors mygame/errors mygame/tmp].each { |dir| touch(*dir.split("/"), "x") }
    touch("samples", "keep.rb")

    removed = runner.clean

    assert_equal %w[builds errors logs mygame/errors mygame/tmp tmp], removed.sort
    assert File.file?(File.join(@root, "samples", "keep.rb"))
    assert File.file?(File.join(@root, "mygame", "app", "main.rb"))
  end
end
