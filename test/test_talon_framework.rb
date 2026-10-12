# frozen_string_literal: true

require "test_helper"

class TestTalonFramework < Minitest::Test
  include EngineFixtures

  Talon = DrTalon::TalonFramework

  def setup
    @dir = File.realpath(Dir.mktmpdir)
    @root = build_project(@dir)
    @project = DrTalon::Project.new(@root)
    @main = File.join(@root, "mygame", "app", "main.rb")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def declare(content)
    File.write(File.join(@root, "mygame", "dependencies.rb"), content)
  end

  def block(*lines)
    [Talon::BEGIN_MARKER, *lines, Talon::END_MARKER].join("\n")
  end

  def test_names
    assert_equal %w[MainMenu main_menu], Talon.names("MainMenu")
    assert_equal %w[MainMenu main_menu], Talon.names("main_menu")
    assert_equal %w[EnemyShip enemy_ship], Talon.names("enemy-ship")
    assert_equal %w[Hud hud], Talon.names("hud")
    assert_equal %w[Level2 level2], Talon.names("Level2")
    ["9lives", "Foo::Bar", "a b", ""].each { |bad| assert_raises(DrTalon::Error) { Talon.names(bad) } }
  end

  def test_used_by_the_talon_dependency
    refute Talon.used_by?(@project)

    declare(%(github "asimmons91/talon", path: "lib"\n))
    assert Talon.used_by?(@project)

    assert_equal "vendor/talon/talon.rb", Talon.require_path(@project)

    declare(%(github :asimmons91, :talon, "lib", destination: "vendor/framework"\n))
    assert Talon.used_by?(@project), "Foodchain style, renamed"
    assert_equal "vendor/framework/talon.rb", Talon.require_path(@project)

    declare(%(path "../talon/lib"\n))
    assert Talon.used_by?(@project), "a local talon checkout"
    assert_equal "vendor/lib/talon.rb", Talon.require_path(@project)

    declare(%(github "someone/talons"\n))
    refute Talon.used_by?(@project)

    declare("this is not valid ruby (")
    refute Talon.used_by?(@project)
  end

  def test_require_used
    assert_raises(Talon::NotUsed) { Talon.require_used!(@project) }
  end

  def test_add_require_keeps_kinds_in_load_order
    File.write(@main, "require \"vendor/talon/talon.rb\"\n\n#{block}\n\ndef tick(args); end\n")

    assert_equal :added, Talon.add_require(@main, %(require "app/scenes/title.rb"))
    assert_equal :added, Talon.add_require(@main, %(require "app/components/spin.rb"))
    assert_equal :added, Talon.add_require(@main, %(require "app/prefabs/ship.rb"))
    assert_equal :added, Talon.add_require(@main, %(require "app/components/health.rb"))
    assert_equal :present, Talon.add_require(@main, %(require "app/scenes/title.rb"))

    expected = block(%(require "app/components/health.rb"), %(require "app/components/spin.rb"),
      %(require "app/prefabs/ship.rb"), %(require "app/scenes/title.rb"))
    assert_includes File.read(@main), expected
    assert File.read(@main).end_with?("\n\ndef tick(args); end\n")
  end

  def test_add_require_keeps_hand_written_lines_first
    File.write(@main, block(%(require "lib/helpers.rb"), %(require "app/scenes/b.rb")) + "\n")

    Talon.add_require(@main, %(require "app/components/a.rb"))

    assert_includes File.read(@main),
      block(%(require "lib/helpers.rb"), %(require "app/components/a.rb"), %(require "app/scenes/b.rb"))
  end

  def test_add_require_without_a_block
    File.write(@main, "def tick(args); end\n")

    assert_equal :no_block, Talon.add_require(@main, %(require "app/scenes/title.rb"))
    assert_equal "def tick(args); end\n", File.read(@main)
  end
end
