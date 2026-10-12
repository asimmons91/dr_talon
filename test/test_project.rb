# frozen_string_literal: true

require "test_helper"

class TestProject < Minitest::Test
  include EngineFixtures

  Project = DrTalon::Project

  def setup
    @dir = File.realpath(Dir.mktmpdir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_layouts
    assert_equal :full, Project.new(build_project(@dir, layout: :full)).layout
    assert_equal :game_only, Project.new(build_project(@dir, layout: :game_only)).layout
    assert_nil Project.new(@dir).layout
  end

  def test_game_dir_depends_on_layout
    full = build_project(@dir, layout: :full)
    game_only = build_project(@dir, layout: :game_only)

    assert_equal File.join(full, "mygame"), Project.new(full).game_dir
    assert_equal game_only, Project.new(game_only).game_dir
  end

  def test_find_walks_up_to_the_pin
    root = build_project(@dir)
    File.write(File.join(root, Project::PIN_FILE), "7.23-pro\n")

    assert_equal root, Project.find(File.join(root, "mygame", "app")).root
    assert_nil Project.find(@dir)
  end

  def test_locate_falls_back_to_an_unpinned_game_directory
    root = build_project(@dir)

    assert_equal root, Project.locate(root).root
  end

  def test_locate_refuses_directories_that_are_not_games
    error = assert_raises(Project::NotFound) { Project.locate(@dir) }

    assert_match(/doesn't look like a DragonRuby project/, error.message)
  end

  def test_pin_round_trip_omits_the_platform
    project = Project.new(build_project(@dir))
    installation = DrTalon::Engine::Installation.new(
      version: "7.23", tier: "pro", platform: "linux-amd64", path: "/x",
      build_date: nil, git_sha: nil, sha256: nil, source: nil, imported_at: nil
    )

    assert_nil project.pin
    project.pin!(installation)

    assert_equal "7.23-pro\n", File.read(project.pin_path)
    assert_equal DrTalon::Engine::Spec.new(version: "7.23", tier: "pro", platform: nil), project.pin
  end

  def test_pin_skips_comments_and_blank_lines
    project = Project.new(build_project(@dir))
    File.write(project.pin_path, "# engine for this game\n\n7.22-indie\n")

    assert_equal "7.22-indie", project.pin.to_s
  end

  def test_empty_or_invalid_pins_raise
    project = Project.new(build_project(@dir))

    File.write(project.pin_path, "\n")
    assert_raises(DrTalon::Error) { project.pin }

    File.write(project.pin_path, "newest\n")
    assert_raises(DrTalon::Error) { project.pin }
  end
end
