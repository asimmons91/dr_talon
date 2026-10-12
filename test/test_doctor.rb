# frozen_string_literal: true

require "test_helper"

class TestDoctor < Minitest::Test
  include EngineFixtures

  PLACEHOLDER_METADATA = <<~TXT
    # devid=commented_out
    devid=your_itchio_username
    devtitle=Your Itch.io Display Name
    gameid=your_itchio_game_id
    gametitle=Your Game Title
  TXT

  def setup
    @dir = Dir.mktmpdir
    @store = DrTalon::Engine::Store.new(File.join(@dir, "engines"), host_platform: "linux-amd64")
    @engine = import_engine(@store, @dir)
    @project = DrTalon::Project.new(build_project(@dir))
    write_metadata("devid=me\ndevtitle=Me\ngameid=game\ngametitle=Game\n")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write_metadata(contents)
    path = File.join(@project.game_dir, "metadata", "game_metadata.txt")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def checks
    DrTalon::Doctor.new(@project, @store, host_platform: "linux-amd64").checks
  end

  def statuses
    checks.map(&:status)
  end

  def messages(status)
    checks.select { |check| check.status == status }.map(&:message)
  end

  def install
    DrTalon::Engine::Materializer.new(@project).install(@engine)
    @project.pin!(@engine)
  end

  def test_healthy_project
    install

    assert_equal %i[ok ok ok ok], statuses
  end

  def test_missing_pin
    assert_match(/No \.dragonruby-version/, messages(:error).first)
  end

  def test_pinned_engine_not_cached
    File.write(@project.pin_path, "7.99-pro\n")

    assert_match(/no matching linux-amd64 engine is cached/, messages(:error).first)
  end

  def test_pinned_but_not_installed
    @project.pin!(@engine)

    assert_match(/isn't installed in the project/, messages(:error).first)
  end

  def test_installed_engine_differs_from_pin
    install
    newer = import_engine(@store, @dir, version: "7.24")
    @project.pin!(newer)

    assert_match(/has 7\.23-pro-linux-amd64 installed but .* pins 7\.24-pro/, messages(:error).first)
  end

  def test_missing_engine_files
    install
    File.unlink(@project.path("VERSION.txt"))

    assert_match(/1 engine file is missing \(e\.g\. VERSION\.txt\)/, messages(:error).first)
  end

  def test_binary_must_be_executable
    install
    File.chmod(0o644, @project.path("dragonruby"))

    assert_match(/isn't executable/, messages(:error).first)
  end

  def test_metadata_placeholders_are_warnings
    install
    write_metadata(PLACEHOLDER_METADATA)

    assert_equal ["game_metadata.txt doesn't set devid, devtitle, gameid, gametitle yet (needed to publish)"],
      messages(:warning)
    assert_empty messages(:error)
  end

  def test_commented_out_metadata_counts_as_unset
    install
    write_metadata("# devid=me\ndevtitle=Me\ngameid=game\ngametitle=Game\n")

    assert_equal ["game_metadata.txt doesn't set devid yet (needed to publish)"], messages(:warning)
  end

  def test_missing_metadata_is_a_warning_for_full_layouts
    install
    FileUtils.rm_rf(File.join(@project.game_dir, "metadata"))

    assert_match(/No metadata\/game_metadata\.txt/, messages(:warning).first)
  end
end
