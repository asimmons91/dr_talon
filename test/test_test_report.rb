# frozen_string_literal: true

require "test_helper"

# Fixtures are real DragonRuby 7.23 output.
class TestTestReport < Minitest::Test
  def report(name)
    DrTalon::TestReport.parse(File.read(File.join(__dir__, "fixtures", "dragonruby", "#{name}.log")))
  end

  def test_passed
    r = report("passed")

    assert_equal :passed, r.status
    assert_equal [1, 0, 0], [r.passed, r.failed, r.inconclusive]
    assert_empty r.details
    assert_predicate r, :passed?
  end

  def test_failed_assertion
    r = report("failed")

    assert_equal :failed, r.status
    assert_equal [1, 1], [r.passed, r.failed]
    assert r.details.start_with?("**** Test name: FailingTests#test_fails")
    assert_includes r.details, "one is not two"
    assert_includes r.details, "test/failing_tests.rb:9:in test_fails"
    refute_includes r.details, "[Engine]"
    refute_includes r.details, "- [Game] "
    refute_match(/\n\n\n/, r.details)
  end

  def test_exception_inside_a_test_is_a_failure
    r = report("raised")

    assert_equal :failed, r.status
    assert_equal [0, 1], [r.passed, r.failed]
    assert_includes r.details, "boom"
  end

  def test_syntax_error_is_an_error
    r = report("syntax_error")

    assert_equal :error, r.status
    assert_includes r.details, "syntax error"
    refute_predicate r, :passed?
  end

  def test_file_without_tests
    r = report("no_tests")

    assert_equal :no_tests, r.status
    refute_predicate r, :passed?
  end

  def test_output_without_a_summary_is_an_error
    r = DrTalon::TestReport.parse("* [Engine] Log started\n* [Engine] Logging shutting down\n")

    assert_equal :error, r.status
    assert_match(/didn't print a test summary/, r.details)
  end

  def test_timeout
    r = DrTalon::TestReport.timeout("partial")

    assert_equal :timeout, r.status
    assert_equal "partial", r.output
    refute_predicate r, :passed?
  end
end
