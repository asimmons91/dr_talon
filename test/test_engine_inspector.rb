# frozen_string_literal: true

require "test_helper"

class TestEngineInspector < Minitest::Test
  include EngineFixtures

  Inspector = DrTalon::Engine::Inspector

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_reads_details_from_the_engine
    root = build_engine_dir(@dir)

    details = Inspector.new(root, hints: ["dragonruby-pro-linux-amd64"]).details

    assert_equal(
      {version: "7.23", tier: "pro", platform: "linux-amd64", build_date: BUILD_DATE, git_sha: GIT_SHA},
      details
    )
  end

  def test_version_is_the_first_changelog_heading
    root = build_engine_dir(@dir, version: "6.58.1")

    assert_equal "6.58.1", Inspector.new(root, tier: "pro").details[:version]
  end

  def test_missing_version_heading_is_invalid
    root = build_engine_dir(@dir)
    File.write(File.join(root, "CHANGELOG-CURR.txt"), "nothing here\n")

    error = assert_raises(DrTalon::Engine::InvalidEngine) { Inspector.new(root, tier: "pro").details }
    assert_match(/version heading/, error.message)
  end

  def test_tier_detection_needs_an_unambiguous_hint
    root = build_engine_dir(@dir)

    assert_equal "indie", Inspector.new(root, hints: ["dragonruby-indie-linux-amd64"]).details[:tier]
    assert_raises(DrTalon::Engine::InvalidEngine) { Inspector.new(root).details }
    assert_raises(DrTalon::Engine::InvalidEngine) { Inspector.new(root, hints: %w[dragonruby-pro x-indie]).details }
  end

  def test_jam_tier_from_the_itch_zip_name
    root = build_engine_dir(@dir)

    assert_equal "jam", Inspector.new(root, hints: ["dragonruby-gtk-linux-amd64-jam"]).details[:tier]
  end

  def test_tier_is_not_matched_inside_other_words
    root = build_engine_dir(@dir)

    assert_raises(DrTalon::Engine::InvalidEngine) { Inspector.new(root, hints: ["projects"]).details }
  end

  def test_explicit_tier_and_platform_win
    root = build_engine_dir(@dir)

    details = Inspector.new(root, hints: ["dragonruby-pro"], tier: "standard", platform: "linux-arm64").details

    assert_equal %w[standard linux-arm64], details.values_at(:tier, :platform)
  end

  def test_unknown_explicit_tier_is_rejected
    root = build_engine_dir(@dir)

    assert_raises(DrTalon::Engine::InvalidEngine) { Inspector.new(root, tier: "gold").details }
  end

  def test_platform_needs_a_recognizable_directory_name
    root = build_engine_dir(@dir)
    renamed = File.join(@dir, "engine")
    File.rename(root, renamed)

    error = assert_raises(DrTalon::Engine::InvalidEngine) { Inspector.new(renamed, tier: "pro").details }
    assert_match(/--platform/, error.message)
  end

  def test_find_root_accepts_the_root_or_its_parent
    root = build_engine_dir(@dir)

    assert_equal root, Inspector.find_root(root)
    assert_equal root, Inspector.find_root(@dir)
  end

  def test_find_root_recognizes_windows_binaries
    root = build_engine_dir(@dir, platform: "windows-amd64", binary: "dragonruby.exe")

    assert_equal root, Inspector.find_root(@dir)
  end

  def test_find_root_rejects_non_engines_and_multiple_engines
    assert_raises(DrTalon::Engine::InvalidEngine) { Inspector.find_root(@dir) }

    build_engine_dir(@dir, platform: "linux-amd64")
    build_engine_dir(@dir, platform: "macos")
    error = assert_raises(DrTalon::Engine::InvalidEngine) { Inspector.find_root(@dir) }
    assert_match(/more than one/, error.message)
  end
end
