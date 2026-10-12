# frozen_string_literal: true

module DrTalon
  # The outcome of one +dragonruby --test FILE+ run, read from its output.
  # DragonRuby exits 0 whether tests pass, fail or the file doesn't load, so
  # the output is the only signal.
  #
  # @!attribute [r] status
  #   @return [Symbol] +:passed+, +:failed+, +:error+ (an exception outside a
  #     test, such as a syntax error), +:no_tests+ or +:timeout+
  # @!attribute [r] passed
  #   @return [Integer]
  # @!attribute [r] failed
  #   @return [Integer]
  # @!attribute [r] inconclusive
  #   @return [Integer] tests that made no assertions
  # @!attribute [r] details
  #   @return [String] failure or exception details, empty when passing
  # @!attribute [r] output
  #   @return [String] everything DragonRuby printed
  TestReport = Data.define(:status, :passed, :failed, :inconclusive, :details, :output)

  class TestReport
    SUMMARY = /\] (\d+) test\(s\) (passed|failed|inconclusive)\./
    EXCEPTION = /^(?:- \[Game\] )?\* (?:EXCEPTION|ERROR):/
    NO_TESTS = "No tests were found"
    ENGINE_LINE = /^[-*?] \[Engine\]/

    # @param output [String]
    # @return [TestReport]
    def self.parse(output)
      counts = Hash.new(0)
      output.scan(SUMMARY) { |count, kind| counts[kind] = count.to_i }
      summary = output.match?(SUMMARY)
      lines = output.lines(chomp: true)

      status, details =
        if (start = lines.index { |line| line.match?(EXCEPTION) })
          [:error, section(lines, start)]
        elsif !summary && output.include?(NO_TESTS)
          [:no_tests, ""]
        elsif !summary
          [:error, "DragonRuby didn't print a test summary."]
        elsif counts["failed"].positive?
          [:failed, section(lines, lines.index { |line| line.match?(/\] \d+ test\(s\) failed\./) } + 1)]
        else
          [:passed, ""]
        end

      new(status: status, passed: counts["passed"], failed: counts["failed"],
        inconclusive: counts["inconclusive"], details: details, output: output)
    end

    # @param output [String] whatever was printed before the run was stopped
    # @return [TestReport]
    def self.timeout(output)
      new(status: :timeout, passed: 0, failed: 0, inconclusive: 0, details: "", output: output)
    end

    # @return [Boolean]
    def passed?
      status == :passed
    end

    # Lines from +start+ up to DragonRuby's shutdown messages, without the
    # "- [Game] " log prefixes and with runs of blank lines collapsed.
    def self.section(lines, start)
      finish = ((start + 1)...lines.size).find { |i| lines[i].match?(ENGINE_LINE) } || lines.size
      lines[start...finish]
        .map { |line| line.sub(/\A- \[Game\] /, "").rstrip }
        .chunk_while { |a, b| a.empty? && b.empty? }.map(&:first)
        .join("\n").strip
    end
    private_class_method :section
  end
end
