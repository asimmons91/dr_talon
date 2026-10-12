# frozen_string_literal: true

require "test_helper"

class TestCLI < Minitest::Test
  def test_version_prints_the_version
    out, _err = capture_io { DrTalon::CLI.start(["version"]) }

    assert_equal "talon #{DrTalon::VERSION}\n", out
  end

  def test_version_flags_map_to_version
    %w[-v --version].each do |flag|
      out, _err = capture_io { DrTalon::CLI.start([flag]) }

      assert_equal "talon #{DrTalon::VERSION}\n", out
    end
  end

  def test_exits_non_zero_on_failure
    assert_predicate DrTalon::CLI, :exit_on_failure?
  end
end
