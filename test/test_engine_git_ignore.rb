# frozen_string_literal: true

require "test_helper"

class TestEngineGitIgnore < Minitest::Test
  GitIgnore = DrTalon::Engine::GitIgnore

  FILES = %w[dragonruby font.ttf .dragonruby/stubs/linux-amd64 samples/a/main.rb samples/b/main.rb].freeze

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, ".gitignore")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_patterns_are_top_level_entries_plus_talon
    assert_equal %w[/.talon/ /.dragonruby/ /dragonruby /font.ttf /samples/], GitIgnore.patterns(FILES)
  end

  def test_write_appends_to_an_existing_file
    File.write(@path, "/logs/\n")

    GitIgnore.write(@path, %w[dragonruby])

    assert_equal "/logs/\n\n#{GitIgnore::BEGIN_MARKER}\n/.talon/\n/dragonruby\n#{GitIgnore::END_MARKER}\n", File.read(@path)
  end

  def test_write_replaces_the_block_and_keeps_surrounding_lines
    File.write(@path, "/logs/\n")
    GitIgnore.write(@path, FILES)
    File.write(@path, File.read(@path) + "/after/\n")

    GitIgnore.write(@path, %w[dragonruby])

    content = File.read(@path)
    assert_equal 1, content.scan(GitIgnore::BEGIN_MARKER).size
    assert content.start_with?("/logs/\n")
    assert content.end_with?("#{GitIgnore::END_MARKER}\n/after/\n")
    refute_includes content, "/samples/"
  end

  def test_refresh_only_touches_files_with_a_block
    File.write(@path, "/logs/\n")

    refute GitIgnore.refresh(@path, FILES)
    assert_equal "/logs/\n", File.read(@path)

    GitIgnore.write(@path, FILES)
    assert GitIgnore.refresh(@path, %w[dragonruby])
    refute_includes File.read(@path), "/samples/"
  end

  def test_refresh_ignores_a_missing_file
    refute GitIgnore.refresh(@path, FILES)
    refute File.exist?(@path)
  end
end
