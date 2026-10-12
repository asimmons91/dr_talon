# frozen_string_literal: true

require "test_helper"

class TestEngineImporter < Minitest::Test
  include EngineFixtures

  Engine = DrTalon::Engine

  def setup
    @dir = Dir.mktmpdir
    @store = Engine::Store.new(File.join(@dir, "engines"))
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def import(source, **options)
    Engine::Importer.new(@store, **options).import(source)
  end

  def test_imports_a_zip
    zip = build_engine_zip(@dir)

    result = import(zip)
    installation = result.installation

    assert_equal :installed, result.status
    assert_equal "7.23-pro-linux-amd64", installation.id
    assert_equal File.join(@store.root, "7.23-pro-linux-amd64"), installation.path
    assert_equal "dragonruby-pro-linux-amd64.zip", installation.source
    assert_equal Digest::SHA256.file(zip).hexdigest, installation.sha256
    assert_equal installation, @store.get(installation.id)
  end

  def test_keeps_executables_and_hidden_files
    path = import(build_engine_zip(@dir)).installation.path

    assert File.executable?(File.join(path, "dragonruby"))
    assert File.file?(File.join(path, ".dragonruby", "stubs", "linux-amd64"))
    assert File.file?(File.join(path, "mygame", "app", "main.rb"))
  end

  def test_imports_an_extracted_directory_using_the_parent_name_as_a_hint
    parent = File.join(@dir, "dragonruby-indie-linux-amd64")
    root = build_engine_dir(parent)

    installation = import(root).installation

    assert_equal "7.23-indie-linux-amd64", installation.id
    assert_nil installation.sha256
    assert File.directory?(root), "the source directory is left in place"
  end

  def test_reimporting_the_same_zip_is_a_no_op
    zip = build_engine_zip(@dir)
    first = import(zip).installation

    result = import(zip)

    assert_equal :unchanged, result.status
    assert_equal first, result.installation
  end

  def test_a_different_source_for_the_same_id_needs_force
    import(build_engine_zip(@dir))
    other = build_engine_dir(File.join(@dir, "dragonruby-pro-linux-amd64"))

    assert_raises(Engine::AlreadyInstalled) { import(other) }

    result = import(other, force: true)
    assert_equal :replaced, result.status
    assert_nil result.installation.sha256
  end

  def test_tier_override_applies_to_unhinted_names
    zip = build_engine_zip(@dir, name: "engine.zip")

    assert_raises(Engine::InvalidEngine) { import(zip) }
    assert_equal "7.23-standard-linux-amd64", import(zip, tier: "standard").installation.id
  end

  def test_rejects_missing_paths_and_non_zip_files
    assert_raises(DrTalon::Error) { import(File.join(@dir, "missing.zip")) }

    bogus = File.join(@dir, "bogus.zip")
    File.write(bogus, "not a zip")
    assert_raises(DrTalon::Error) { import(bogus) }
  end

  def test_failed_imports_leave_no_staging_behind
    zip = build_engine_zip(@dir, name: "engine.zip")

    assert_raises(Engine::InvalidEngine) { import(zip) }

    assert_empty Dir.children(@store.root)
  end
end
