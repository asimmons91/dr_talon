# frozen_string_literal: true

require "test_helper"

class TestCLIGenerate < Minitest::Test
  include EngineFixtures

  def setup
    @dir = File.realpath(Dir.mktmpdir)
    @root = build_project(@dir)
    @game = File.join(@root, "mygame")
    File.write(File.join(@game, "dependencies.rb"), %(github "asimmons91/talon", path: "lib"\n))
    File.write(File.join(@game, "app", "main.rb"),
      [DrTalon::TalonFramework::BEGIN_MARKER, DrTalon::TalonFramework::END_MARKER, "", "def tick(args); end", ""].join("\n"))
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def talon(*args)
    Dir.chdir(@root) { capture_io { DrTalon::CLI.start(args) } }
  end

  def read(*relative)
    File.read(File.join(@game, *relative))
  end

  def test_scene
    out, _err = talon("generate", "scene", "MainMenu")

    assert_match(%r{create\s+app/scenes/main_menu\.rb}, out)
    assert_includes read("app", "scenes", "main_menu.rb"), "class MainMenu < Talon::Scene"
    test = read("tests", "scenes", "main_menu_tests.rb")
    assert_includes test, %(require "vendor/talon/talon.rb")
    assert_includes test, %(require "app/scenes/main_menu.rb")
    assert_includes test, "class MainMenuTests"
    assert_includes test, "def test_main_menu_is_entered_by_the_game(args, assert)"
    assert_includes read("app", "main.rb"), %(require "app/scenes/main_menu.rb")
  end

  def test_component_and_prefab_with_the_g_alias
    talon("g", "component", "health")
    talon("g", "prefab", "enemy-ship")

    assert_includes read("app", "components", "health.rb"), "class Health < Talon::Component"
    assert_includes read("tests", "components", "health_tests.rb"), "g.add(Health)"
    assert_includes read("app", "prefabs", "enemy_ship.rb"), "module EnemyShip"
    assert_includes read("app", "prefabs", "enemy_ship.rb"), "def self.call(go)"
    assert_includes read("tests", "prefabs", "enemy_ship_tests.rb"), "scene.spawn(:enemy_ship, EnemyShip, x: 10, y: 20)"
    main = read("app", "main.rb")
    assert_operator main.index("components/health.rb"), :<, main.index("prefabs/enemy_ship.rb")
  end

  def test_tests_require_talon_from_where_it_is_vendored
    File.write(File.join(@game, "dependencies.rb"), %(github "asimmons91/talon", path: "lib", as: "framework"\n))

    talon("generate", "component", "Health")

    assert_includes read("tests", "components", "health_tests.rb"), %(require "vendor/framework/talon.rb")
  end

  def test_skip_test
    talon("generate", "component", "Health", "--skip-test")

    refute File.exist?(File.join(@game, "tests", "components", "health_tests.rb"))
  end

  def test_existing_files_need_force
    talon("generate", "scene", "Title")
    File.write(File.join(@game, "app", "scenes", "title.rb"), "# mine")

    assert_raises(SystemExit) { talon("generate", "scene", "Title") }
    assert_equal "# mine", read("app", "scenes", "title.rb")

    talon("generate", "scene", "Title", "--force")
    assert_includes read("app", "scenes", "title.rb"), "class Title < Talon::Scene"
  end

  def test_without_a_requires_block_prints_the_line
    File.write(File.join(@game, "app", "main.rb"), "def tick(args); end\n")

    out, _err = talon("generate", "scene", "Title")

    assert_match(%r{Add this to app/main\.rb.*\n  require "app/scenes/title\.rb"}, out)
    assert_equal "def tick(args); end\n", read("app", "main.rb")
  end

  def test_requires_talon
    File.write(File.join(@game, "dependencies.rb"), "")

    assert_raises(SystemExit) { talon("generate", "scene", "Title") }
    refute File.exist?(File.join(@game, "app", "scenes"))
  end

  def test_bad_names
    assert_raises(SystemExit) { talon("generate", "scene", "9lives") }
  end
end
