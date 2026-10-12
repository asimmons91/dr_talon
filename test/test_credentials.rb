# frozen_string_literal: true

require "test_helper"

class TestCredentials < Minitest::Test
  Credentials = DrTalon::Credentials

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "config", "credentials.yml")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_environment_wins_and_needs_both_variables
    env = {"DRAGONRUBY_USERNAME" => "env-user", "DRAGONRUBY_PASSWORD" => "env-pass"}
    Credentials.new(username: "file-user", password: "file-pass", source: :prompt).save(@path)

    assert_equal ["env-user", :env], Credentials.lookup(env: env, path: @path).then { [_1.username, _1.source] }
    assert_equal ["file-user", :file], Credentials.lookup(env: env.except("DRAGONRUBY_PASSWORD"), path: @path).then { [_1.username, _1.source] }
    assert_nil Credentials.lookup(env: {}, path: File.join(@dir, "missing.yml"))
  end

  def test_save_writes_an_owner_only_file
    Credentials.new(username: "me", password: "pw", source: :prompt).save(@path)

    assert_equal 0o600, File.stat(@path).mode & 0o777
    assert_equal({"username" => "me", "password" => "pw"}, YAML.safe_load_file(@path))
  end

  def test_save_tightens_an_existing_loose_file
    FileUtils.mkdir_p(File.dirname(@path))
    File.write(@path, "old")
    File.chmod(0o644, @path)

    Credentials.new(username: "me", password: "pw", source: :prompt).save(@path)

    assert_equal 0o600, File.stat(@path).mode & 0o777
  end

  def test_refuses_files_others_can_read
    Credentials.new(username: "me", password: "pw", source: :prompt).save(@path)
    File.chmod(0o640, @path)

    error = assert_raises(Credentials::InsecureFile) { Credentials.load(@path) }
    assert_match(/chmod 600/, error.message)
  end

  def test_rejects_incomplete_files
    FileUtils.mkdir_p(File.dirname(@path))
    File.write(@path, "username: me\n")
    File.chmod(0o600, @path)

    assert_raises(DrTalon::Error) { Credentials.load(@path) }
  end

  def test_delete
    refute Credentials.delete(@path)
    Credentials.new(username: "me", password: "pw", source: :prompt).save(@path)

    assert Credentials.delete(@path)
    refute File.exist?(@path)
  end

  def test_inspect_hides_the_password
    credentials = Credentials.new(username: "me", password: "hunter2", source: :env)

    refute_includes credentials.inspect, "hunter2"
    refute_includes credentials.to_s, "hunter2"
  end
end
