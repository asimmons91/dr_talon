# frozen_string_literal: true

require "test_helper"

class TestEngineStore < Minitest::Test
  Engine = DrTalon::Engine

  def setup
    @dir = Dir.mktmpdir
    @store = Engine::Store.new(File.join(@dir, "engines"), host_platform: "linux-amd64")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def add(version, tier: "pro", platform: "linux-amd64")
    installation = Engine::Installation.new(
      version: version, tier: tier, platform: platform, path: @store.path_for("#{version}-#{tier}-#{platform}"),
      build_date: nil, git_sha: nil, sha256: nil, source: nil, imported_at: nil
    )
    FileUtils.mkdir_p(installation.path)
    installation.write_metadata
    installation
  end

  def test_empty_when_the_store_does_not_exist
    assert_empty @store.installations
  end

  def test_installations_are_newest_first_by_numeric_version
    add("7.9")
    add("7.23")
    add("6.58")

    assert_equal %w[7.23 7.9 6.58], @store.installations.map(&:version)
  end

  def test_more_capable_tiers_sort_first_within_a_version
    add("7.23", tier: "jam")
    add("7.23", tier: "standard")
    add("7.23", tier: "pro")
    add("7.23", tier: "indie")
    add("7.22", tier: "pro")

    assert_equal %w[7.23-pro 7.23-indie 7.23-standard 7.23-jam 7.22-pro],
      @store.installations.map { |i| "#{i.version}-#{i.tier}" }
    assert_equal "pro", @store.latest_native.tier
    assert_equal "7.23-jam-linux-amd64", @store.find("7.23-jam").id
  end

  def test_ignores_staging_and_unrelated_directories
    add("7.23")
    FileUtils.mkdir_p(File.join(@store.root, ".staging-123"))
    FileUtils.mkdir_p(File.join(@store.root, "notes"))

    assert_equal ["7.23-pro-linux-amd64"], @store.installations.map(&:id)
  end

  def test_find_by_partial_spec
    add("7.23")
    add("7.22")

    assert_equal "7.23-pro-linux-amd64", @store.find("7.23").id
    assert_equal "7.22-pro-linux-amd64", @store.find("7.22-pro").id
  end

  def test_find_prefers_the_host_platform
    add("7.23", platform: "macos")
    add("7.23", platform: "linux-amd64")

    assert_equal "7.23-pro-linux-amd64", @store.find("7.23").id
    assert_equal "7.23-pro-macos", @store.find("7.23-pro-macos").id
  end

  def test_find_uses_the_only_match_even_for_another_platform
    add("7.23", platform: "macos")

    assert_equal "7.23-pro-macos", @store.find("7.23").id
  end

  def test_find_reports_ambiguity_and_absence
    add("7.23", tier: "pro")
    add("7.23", tier: "indie")

    assert_raises(Engine::Ambiguous) { @store.find("7.23") }
    assert_equal "7.23-indie-linux-amd64", @store.find("7.23-indie").id
    assert_raises(Engine::NotFound) { @store.find("7.1") }
  end

  def test_find_rejects_malformed_specs
    assert_raises(DrTalon::Error) { @store.find("latest") }
  end

  def test_remove_deletes_the_engine
    installation = add("7.23")

    @store.remove(installation)

    assert_empty @store.installations
    refute File.exist?(installation.path)
  end

  def test_stage_cleans_up_even_on_failure
    staged = nil
    assert_raises(RuntimeError) do
      @store.stage do |dir|
        staged = dir
        raise "boom"
      end
    end

    refute File.exist?(staged)
  end
end
