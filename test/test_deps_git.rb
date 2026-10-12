# frozen_string_literal: true

require "test_helper"

class TestDepsGit < Minitest::Test
  include DepsFixtures

  def setup
    @dir = File.realpath(Dir.mktmpdir)
    @first = commit_to(@dir, "o", "r", {"lib/a.rb" => "1"}, tag: "v1")
    @second = commit_to(@dir, "o", "r", {"lib/a.rb" => "2"})
    @url = "file://#{@dir}/o/r.git"
    @git = DrTalon::Deps::Git.new
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_resolves_default_branch_branch_tag_and_full_sha
    assert_equal @second, @git.resolve(@url, nil)
    assert_equal @second, @git.resolve(@url, "main")
    assert_equal @first, @git.resolve(@url, "v1"), "annotated tags resolve to their commit"
    assert_equal @first, @git.resolve(@url, @first.upcase)
  end

  def test_unknown_refs_and_abbreviated_shas
    assert_raises(DrTalon::Deps::FetchError) { @git.resolve(@url, "nope") }

    error = assert_raises(DrTalon::Deps::FetchError) { @git.resolve(@url, @first[0, 7]) }
    assert_match(/all 40 characters/, error.message)
  end

  def test_checkout_a_commit
    target = File.join(@dir, "checkout")

    @git.checkout(@url, @first, target)

    assert_equal "1", File.read(File.join(target, "lib", "a.rb"))
  end

  def test_unreachable_remote
    assert_raises(DrTalon::Deps::FetchError) { @git.resolve("file://#{@dir}/missing.git", nil) }
  end
end
