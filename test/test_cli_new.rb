# frozen_string_literal: true

require "test_helper"
require "stringio"
require "minitest/mock"

class TestCLINew < Minitest::Test
  include EngineFixtures
  include DepsFixtures

  def setup
    @dir = File.realpath(Dir.mktmpdir)
    @previous_home = ENV["DR_TALON_HOME"]
    ENV["DR_TALON_HOME"] = File.join(@dir, "home")
    capture_io { DrTalon::CLI.start(["engine", "import", build_engine_zip(@dir)]) }
  end

  def teardown
    ENV["DR_TALON_HOME"] = @previous_home
    FileUtils.rm_rf(@dir)
  end

  def talon(*args, stdin: "")
    previous = $stdin
    $stdin = StringIO.new(stdin)
    capture_io { DrTalon::CLI.start(args) }
  ensure
    $stdin = previous
  end

  def new_project(name, *args, **options)
    Dir.chdir(@dir) { talon("new", name, "--skip-git", "--skip-bundle", *args, **options) }
    File.join(@dir, name)
  end

  def read(root, *relative)
    File.read(File.join(root, *relative))
  end

  def test_bare_game_layout
    root = new_project("my_game", "--no-commit-engine")

    assert_equal "def tick(args); end\n", read(root, "mygame", "app", "main.rb")
    assert_equal "7.23-pro\n", read(root, ".dragonruby-version")
    assert File.executable?(File.join(root, "dragonruby"))
    %w[Gemfile .editorconfig .gitignore README.md .rubocop.yml .solargraph.yml].each do |file|
      assert File.file?(File.join(root, file)), "expected #{file}"
    end
    assert_equal :full, DrTalon::Project.new(root).layout
  end

  def test_metadata_is_uncommented_and_filled_in
    root = new_project("space-race", "--no-commit-engine", "--dev-id", "austin", "--dev-title", "Austin S")

    metadata = read(root, "mygame", "metadata", "game_metadata.txt")
    assert_includes metadata, "devid=austin\ndevtitle=Austin S\ngameid=space-race\ngametitle=Space Race\nversion=0.1\n"
    assert_includes metadata, "icon=metadata/icon.png"
    assert_includes metadata, "# === Remove the pound sign"
  end

  def test_metadata_leaves_unknown_developer_fields_commented
    root = new_project("my_game", "--no-commit-engine", "--title", "Rocket")

    metadata = read(root, "mygame", "metadata", "game_metadata.txt")
    assert_includes metadata, "# devid=your_itchio_username"
    assert_includes metadata, "gametitle=Rocket"
  end

  def test_dev_fields_default_from_config
    FileUtils.mkdir_p(File.join(@dir, "home", "config"))
    File.write(File.join(@dir, "home", "config", "config.yml"), "dev_id: from_config\ndev_title: Config Name\n")

    root = new_project("my_game", "--no-commit-engine")

    assert_includes read(root, "mygame", "metadata", "game_metadata.txt"), "devid=from_config\ndevtitle=Config Name\n"
  end

  def test_not_committing_ignores_the_engine
    root = new_project("my_game", "--no-commit-engine")

    gitignore = read(root, ".gitignore")
    assert_includes gitignore, DrTalon::Engine::GitIgnore::BEGIN_MARKER
    assert_includes gitignore, "/dragonruby\n"
    assert_includes gitignore, "/.dragonruby/\n"
    assert_includes gitignore, "/.talon/\n"
    assert_includes read(root, "README.md"), "talon engine use"
  end

  def test_committing_leaves_the_engine_tracked
    root = new_project("my_game", "--commit-engine")

    refute_includes read(root, ".gitignore"), DrTalon::Engine::GitIgnore::BEGIN_MARKER
    assert_includes read(root, "README.md"), "is committed with the project"
  end

  def test_asks_about_committing_when_not_told
    out, _err = new_project_with_output("my_game", stdin: "y\n")

    assert_match(/Commit the DragonRuby engine to git\?/, out)
    refute_includes read(File.join(@dir, "my_game"), ".gitignore"), DrTalon::Engine::GitIgnore::BEGIN_MARKER
  end

  def test_answering_no_ignores_the_engine
    new_project_with_output("my_game", stdin: "n\n")

    assert_includes read(File.join(@dir, "my_game"), ".gitignore"), DrTalon::Engine::GitIgnore::BEGIN_MARKER
  end

  def test_talon_template
    remotes = File.join(@dir, "remotes")
    commit_to(remotes, "asimmons91", "talon", {"lib/talon.rb" => "module Talon; end"})

    root = DrTalon::Deps::Context.stub(:default, deps_context(remotes)) { new_project("space", "--template", "talon", "--no-commit-engine") }

    main = read(root, "mygame", "app", "main.rb")
    assert main.start_with?(%(require "vendor/talon/talon.rb"\n))
    assert_includes main, %(#{DrTalon::TalonFramework::BEGIN_MARKER}\nrequire "app/components/spin.rb"\nrequire "app/scenes/title.rb"\n)
    assert_includes main, "Talon::Game.new(Title.new)"
    assert_includes read(root, "mygame", "app", "scenes", "title.rb"), "class Title < Talon::Scene"
    assert_includes read(root, "mygame", "app", "components", "spin.rb"), "class Spin < Talon::Component"
    assert_includes read(root, "mygame", "tests", "scenes", "title_tests.rb"), "class TitleTests"
    assert_includes read(root, "mygame", "dependencies.rb"), %(github "asimmons91/talon", path: "lib")
    assert_equal "module Talon; end", read(root, "mygame", "vendor", "talon", "talon.rb")
    assert_includes read(root, "Gemfile"), %(gem "solargraph-dr_talon")
    assert_includes read(root, ".solargraph.yml"), "- solargraph-dr_talon"
    assert_includes read(root, "README.md"), "built on [Talon]"
    assert DrTalon::TalonFramework.used_by?(DrTalon::Project.new(root))
  end

  def test_talon_template_survives_a_failed_vendor
    out = nil
    root = DrTalon::Deps::Context.stub(:default, deps_context(File.join(@dir, "no-remotes"))) do
      out, _err = new_project_with_output("space", "--template", "talon", "--no-commit-engine")
      File.join(@dir, "space")
    end

    assert_match(/vendoring Talon failed .*talon install/, out)
    assert File.file?(File.join(root, "mygame", "app", "scenes", "title.rb"))
  end

  def test_talon_template_skip_deps_and_plain_games_without_talon
    root = new_project("space", "--template", "talon", "--no-commit-engine", "--skip-deps")
    refute File.exist?(File.join(root, "mygame", "vendor", "talon"))

    plain = new_project("plain", "--no-commit-engine")
    refute_includes read(plain, "Gemfile"), "solargraph-dr_talon"
    refute File.exist?(File.join(plain, "mygame", "dependencies.rb"))
  end

  def test_library_layout
    root = new_project("my-lib", "--lib")

    assert_equal :game_only, DrTalon::Project.new(root).layout
    assert_includes read(root, "lib", "my_lib.rb"), "module MyLib"
    assert_includes read(root, "lib", "my_lib", "version.rb"), 'VERSION = "0.1.0"'
    assert_includes read(root, "app", "main.rb"), 'require "lib/my_lib.rb"'
    assert_includes read(root, "test", "test_helper.rb"), 'require "lib/my_lib.rb"'
    assert_includes read(root, "test", "my_lib_tests.rb"), "class MyLibTests"
    assert File.file?(File.join(root, "dragonruby"))
    refute File.exist?(File.join(root, "mygame"))
    refute File.exist?(File.join(root, ".dragonruby")), "libraries only get the runtime"
  end

  def test_libraries_ignore_the_engine_without_asking
    out, _err = new_project_with_output("my-lib", "--lib")

    refute_match(/Commit the DragonRuby engine/, out)
    assert_includes read(File.join(@dir, "my-lib"), ".gitignore"), "/dragonruby\n"
  end

  def test_default_template_from_config
    FileUtils.mkdir_p(File.join(@dir, "home", "config"))
    File.write(File.join(@dir, "home", "config", "config.yml"), "default_template: lib\n")

    root = new_project("my-lib")

    assert_equal :game_only, DrTalon::Project.new(root).layout
  end

  def test_engine_option_picks_a_cached_engine
    capture_io do
      DrTalon::CLI.start(["engine", "import", build_engine_zip(@dir, name: "dragonruby-pro-linux-amd64-old.zip", version: "7.1")])
    end

    root = new_project("my_game", "--no-commit-engine", "--engine", "7.1")

    assert_equal "7.1-pro\n", read(root, ".dragonruby-version")
  end

  def test_engine_use_refreshes_the_ignore_block
    root = new_project("my_game", "--no-commit-engine")
    capture_io do
      DrTalon::CLI.start(["engine", "import", build_engine_zip(@dir, name: "dragonruby-pro-linux-amd64-old.zip", version: "7.1")])
    end
    File.write(File.join(root, ".gitignore"), read(root, ".gitignore").sub("/VERSION.txt\n", ""))

    Dir.chdir(root) { talon("engine", "use", "7.1") }

    assert_includes read(root, ".gitignore"), "/VERSION.txt\n"
  end

  def test_rejects_bad_names_existing_directories_and_unknown_templates
    assert_raises(SystemExit) { new_project("bad.name", "--no-commit-engine") }

    FileUtils.mkdir_p(File.join(@dir, "taken"))
    File.write(File.join(@dir, "taken", "file"), "x")
    assert_raises(SystemExit) { new_project("taken", "--no-commit-engine") }

    assert_raises(SystemExit) { new_project("my_game", "--template", "nope") }
    refute File.exist?(File.join(@dir, "my_game"))
  end

  def test_fails_without_a_cached_engine
    FileUtils.rm_rf(File.join(@dir, "home", "data"))

    assert_raises(SystemExit) { new_project("my_game", "--no-commit-engine") }
    refute File.exist?(File.join(@dir, "my_game"))
  end

  private

  def new_project_with_output(name, *args, stdin: "")
    Dir.chdir(@dir) { talon("new", name, "--skip-git", "--skip-bundle", *args, stdin: stdin) }
  end
end
