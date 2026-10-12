# frozen_string_literal: true

require "test_helper"

class TestConfig < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "config.yml")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_defaults_without_a_file
    config = DrTalon::Config.load(@path)

    assert_equal "bare", config.default_template
    assert_nil config.dev_id
    assert_nil config.dev_title
  end

  def test_reads_settings
    File.write(@path, "default_template: lib\ndev_id: austin\ndev_title: Austin Simmons\n")

    config = DrTalon::Config.load(@path)

    assert_equal %w[lib austin Austin\ Simmons], [config.default_template, config.dev_id, config.dev_title]
  end

  def test_empty_file_uses_defaults
    File.write(@path, "")

    assert_equal "bare", DrTalon::Config.load(@path).default_template
  end

  def test_rejects_non_mappings_and_bad_yaml
    File.write(@path, "- a\n- b\n")
    assert_raises(DrTalon::Error) { DrTalon::Config.load(@path) }

    File.write(@path, "a: [\n")
    assert_raises(DrTalon::Error) { DrTalon::Config.load(@path) }
  end
end
