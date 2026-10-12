# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "stringio"
require_relative "test_engine_fetchers"

class TestCLIFetch < Minitest::Test
  include EngineFixtures

  # Stdin that claims to be a terminal, for the username/password prompts.
  class FakeTTY < StringIO
    def tty? = true

    def noecho = yield(self)
  end

  def setup
    @dir = File.realpath(Dir.mktmpdir)
    @previous = %w[DR_TALON_HOME DRAGONRUBY_USERNAME DRAGONRUBY_PASSWORD].to_h { |key| [key, ENV[key]] }
    ENV["DR_TALON_HOME"] = File.join(@dir, "home")
    ENV.delete("DRAGONRUBY_USERNAME")
    ENV.delete("DRAGONRUBY_PASSWORD")
    @zip = File.binread(build_engine_zip(@dir, version: "7.24"))
    @server = TestServer.new(
      "/api/download_pro_subscription_linux" => lambda do |headers|
        expected = "Basic #{["me:pw"].pack("m0")}"
        (headers["authorization"] == expected) ? [200, {}, @server.url("/engine.zip")] : [401, {}, "denied"]
      end,
      "/engine.zip" => ->(_) { [200, {}, @zip] },
      "/game" => ->(_) { [200, {}, TestEngineFetchers::ITCH_PAGE] },
      "/game/file/102" => ->(_, _) { [200, {}, JSON.generate("url" => @server.url("/jam.zip"))] },
      "/jam.zip" => ->(_) { [200, {}, @jam_zip] }
    )
    @jam_zip = File.binread(build_engine_zip(@dir, name: "dragonruby-gtk-linux-amd64-jam.zip", version: "7.24"))
  end

  def teardown
    @server.stop
    @previous.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
    FileUtils.rm_rf(@dir)
  end

  # Points the dragonruby.org and itch.io fetchers at the test server.
  def talon(*args, stdin: StringIO.new)
    api = @server.url("/api/download_%<tier>s_subscription_%<os>s")
    real_for = DrTalon::Engine::Fetchers.method(:for)
    real_api = DrTalon::Engine::Fetchers::DragonRubyAPI.method(:new)
    fetchers_for = lambda do |tier, **options|
      case tier
      when "jam" then DrTalon::Engine::Fetchers::ItchJam.new(platform: "linux-amd64", page: @server.url("/game"), **options)
      when "pro", "indie" then real_api.call(tier, platform: "linux-amd64", api: api, **options)
      else real_for.call(tier, **options)
      end
    end
    previous_stdin = $stdin
    $stdin = stdin
    DrTalon::Engine::Fetchers.stub(:for, fetchers_for) do
      DrTalon::Engine::Fetchers::DragonRubyAPI.stub(:new, ->(tier, **o) { real_api.call(tier, platform: "linux-amd64", api: api, **o) }) do
        DrTalon::Engine.stub(:host_platform, "linux-amd64") do
          capture_io { DrTalon::CLI.start(args) }
        end
      end
    end
  ensure
    $stdin = previous_stdin
  end

  def credentials_file
    File.join(@dir, "home", "config", "credentials.yml")
  end

  def test_fetch_with_environment_credentials
    ENV["DRAGONRUBY_USERNAME"] = "me"
    ENV["DRAGONRUBY_PASSWORD"] = "pw"

    out, _err = talon("engine", "fetch", "--tier", "pro")

    assert_match(/Fetched 7\.24-pro-linux-amd64/, out)
    assert_match(/talon engine use 7\.24-pro/, out)
    assert_empty Dir.children(File.join(@dir, "home", "cache", "downloads")), "the zip is removed after import"

    out, _err = talon("engine", "fetch")
    assert_match(/already cached; it's the latest pro release/, out)
  end

  def test_fetch_jam_needs_no_login
    out, _err = talon("engine", "fetch", "--tier", "jam")

    assert_match(/Fetched 7\.24-jam-linux-amd64/, out)
    assert_match(/talon engine use 7\.24-jam/, out)
    refute @server.requests.any? { |path, _| path.start_with?("/api/") }

    out, _err = talon("engine", "fetch")
    assert_match(/already cached; it's the latest jam release/, out)
  end

  def test_keep_zip
    ENV["DRAGONRUBY_USERNAME"] = "me"
    ENV["DRAGONRUBY_PASSWORD"] = "pw"

    talon("engine", "fetch", "--tier", "pro", "--keep-zip")

    assert File.file?(File.join(@dir, "home", "cache", "downloads", "dragonruby-pro-linux-amd64.zip"))
  end

  def test_fetch_with_a_rejected_login
    ENV["DRAGONRUBY_USERNAME"] = "me"
    ENV["DRAGONRUBY_PASSWORD"] = "wrong"

    assert_raises(SystemExit) { talon("engine", "fetch", "--tier", "pro") }
  end

  def test_fetch_prompts_and_can_save_the_login
    out, _err = talon("engine", "fetch", "--tier", "pro", stdin: FakeTTY.new("me\npw\ny\n"))

    assert_match(/Fetched 7\.24-pro-linux-amd64/, out)
    refute_includes out, "pw\n"
    assert_equal 0o600, File.stat(credentials_file).mode & 0o777
  end

  def test_fetch_without_a_terminal_or_login_fails
    assert_raises(SystemExit) { talon("engine", "fetch", "--tier", "pro") }
  end

  def test_login_checks_then_saves_and_logout_deletes
    assert_raises(SystemExit) { talon("engine", "login", stdin: FakeTTY.new("me\nwrong\n")) }
    refute File.exist?(credentials_file)

    out, _err = talon("engine", "login", stdin: FakeTTY.new("me\npw\n"))
    assert_match(/Saved the login for me/, out)
    assert_equal({"username" => "me", "password" => "pw"}, YAML.safe_load_file(credentials_file))

    out, _err = talon("engine", "fetch", "--tier", "pro")
    assert_match(/Fetched/, out)

    out, _err = talon("engine", "logout")
    assert_match(/Deleted/, out)
    refute File.exist?(credentials_file)
  end

  def test_tier_defaults_to_the_newest_cached_engine
    capture_io { DrTalon::CLI.start(["engine", "import", build_engine_zip(@dir, name: "dragonruby-indie-linux-amd64.zip")]) }
    ENV["DRAGONRUBY_USERNAME"] = "me"
    ENV["DRAGONRUBY_PASSWORD"] = "pw"

    assert_raises(SystemExit) { talon("engine", "fetch") } # the test server has no indie route

    assert_equal ["/api/download_indie_subscription_linux"], @server.requests.map(&:first)
  end
end
