# frozen_string_literal: true

require "test_helper"

class TestEngineMaterializer < Minitest::Test
  include EngineFixtures

  Materializer = DrTalon::Engine::Materializer

  def setup
    @dir = Dir.mktmpdir
    @store = DrTalon::Engine::Store.new(File.join(@dir, "engines"))
    @engine = import_engine(@store, @dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def materializer(layout: :full)
    @root = build_project(@dir, layout: layout)
    Materializer.new(DrTalon::Project.new(@root))
  end

  def project_file(*relative)
    File.join(@root, *relative)
  end

  def test_full_layout_gets_everything_but_mygame_and_metadata
    m = materializer

    assert_equal %w[.dragonruby/stubs/linux-amd64 CHANGELOG-CURR.txt VERSION.txt dragonruby], m.files_for(@engine)
  end

  def test_game_only_layout_gets_just_the_runtime
    engine = import_engine(@store, @dir, version: "7.24") do |root|
      File.write(File.join(root, "font.ttf"), "font")
      File.write(File.join(root, "SDL3.dll"), "dll")
    end

    assert_equal %w[SDL3.dll dragonruby font.ttf], materializer(layout: :game_only).files_for(engine)
  end

  def test_skips_finder_metadata
    engine = import_engine(@store, @dir, version: "7.24") do |root|
      File.write(File.join(root, ".dragonruby", ".DS_Store"), "junk")
    end

    refute_includes materializer.files_for(engine), ".dragonruby/.DS_Store"
  end

  def test_install_copies_files_and_writes_a_manifest
    m = materializer

    result = m.install(@engine)

    assert_equal 4, result.copied
    assert_equal 0, result.removed
    assert File.executable?(project_file("dragonruby"))
    assert File.file?(project_file(".dragonruby", "stubs", "linux-amd64"))
    assert_equal "def tick(args); end\n", File.read(project_file("mygame", "app", "main.rb"))
    assert_equal @engine.id, m.manifest.engine
    assert_equal m.files_for(@engine), m.manifest.files
  end

  def test_switching_engines_removes_only_the_previous_engines_files
    old_engine = import_engine(@store, @dir, version: "7.22") do |root|
      FileUtils.mkdir_p(File.join(root, "samples", "old"))
      File.write(File.join(root, "samples", "old", "sample.rb"), "old")
    end
    m = materializer
    m.install(old_engine)
    File.write(project_file("NOTES.md"), "mine")

    result = m.install(@engine)

    assert_equal 5, result.removed
    refute File.exist?(project_file("samples")), "emptied directories are pruned"
    assert_equal "mine", File.read(project_file("NOTES.md"))
    assert File.file?(project_file("mygame", "app", "main.rb"))
    assert_equal "* 7.23", File.readlines(project_file("CHANGELOG-CURR.txt"), chomp: true).first
  end

  def test_pruning_keeps_directories_with_other_files
    old_engine = import_engine(@store, @dir, version: "7.22") do |root|
      FileUtils.mkdir_p(File.join(root, "docs"))
      File.write(File.join(root, "docs", "index.md"), "docs")
    end
    m = materializer
    m.install(old_engine)
    File.write(project_file("docs", "my-notes.md"), "mine")

    m.install(@engine)

    assert_equal ["my-notes.md"], Dir.children(project_file("docs"))
  end

  def test_identical_existing_files_are_adopted
    m = materializer
    FileUtils.cp(File.join(@engine.path, "VERSION.txt"), project_file("VERSION.txt"))

    assert_empty m.conflicts(@engine)
    m.install(@engine)
    assert_includes m.manifest.files, "VERSION.txt"
  end

  def test_differing_files_conflict_and_nothing_changes
    m = materializer
    File.write(project_file("VERSION.txt"), "my own file")

    error = assert_raises(Materializer::Conflict) { m.install(@engine) }

    assert_match(/VERSION\.txt/, error.message)
    assert_equal "my own file", File.read(project_file("VERSION.txt"))
    refute File.exist?(project_file("dragonruby"))
    assert_nil m.manifest
  end

  def test_force_overwrites_conflicts
    m = materializer
    File.write(project_file("VERSION.txt"), "my own file")

    m.install(@engine, force: true)

    assert_equal File.read(File.join(@engine.path, "VERSION.txt")), File.read(project_file("VERSION.txt"))
  end

  def test_files_from_a_previous_install_are_never_conflicts
    m = materializer
    m.install(@engine)
    File.write(project_file("VERSION.txt"), "edited after install")

    assert_empty m.conflicts(@engine)
  end

  def test_manifest_paths_outside_the_project_are_rejected
    m = materializer
    FileUtils.mkdir_p(project_file(".talon"))
    File.write(project_file(".talon", "engine.yml"), {"engine" => "x", "files" => ["../../etc/passwd"]}.to_yaml)

    assert_raises(DrTalon::Error) { m.manifest }
    assert_raises(DrTalon::Error) { m.install(@engine) }
  end
end
