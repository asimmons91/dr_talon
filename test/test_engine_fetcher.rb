# frozen_string_literal: true

require "test_helper"

class TestEngineFetcher < Minitest::Test
  include EngineFixtures

  Fetcher = DrTalon::Engine::Fetcher
  LOGIN = DrTalon::Credentials.new(username: "me", password: "pw", source: :env)

  def setup
    @dir = Dir.mktmpdir
    @zip = File.binread(build_engine_zip(@dir))
    @api_body = nil
    @server = TestServer.new(
      "/api/download_pro_subscription_linux" => lambda do |headers|
        next [401, {}, "HTTP Basic: Access denied.\n"] unless headers["authorization"]

        [200, {}, @api_body || @server.url("/files/engine.zip")]
      end,
      "/api/download_indie_subscription_linux" => ->(_) { [302, {"Location" => "/files/engine.zip"}, ""] },
      "/files/engine.zip" => ->(_) { [200, {}, @zip] },
      "/files/not-a-zip" => ->(_) { [200, {}, "<html>"] }
    )
    @downloads = File.join(@dir, "downloads")
  end

  def teardown
    @server.stop
    FileUtils.rm_rf(@dir)
  end

  def fetcher(platform: "linux-amd64")
    Fetcher.new(downloads_dir: @downloads, platform: platform, api: @server.url("/api/download_%<tier>s_subscription_%<os>s"))
  end

  def test_api_urls_per_platform
    real = ->(platform) { Fetcher.new(platform: platform, downloads_dir: @downloads).api_url("pro") }

    assert_equal "https://dragonruby.org/api/download_pro_subscription_linux", real.call("linux-amd64")
    assert_equal "https://dragonruby.org/api/download_pro_subscription_mac", real.call("macos")
    assert_equal "https://dragonruby.org/api/download_pro_subscription_windows", real.call("windows-amd64")
    assert_raises(DrTalon::Error) { real.call("linux-arm64") }
    assert_raises(DrTalon::Error) { fetcher.api_url("standard") }
  end

  def test_fetch_follows_the_url_in_the_body
    path = fetcher.fetch(LOGIN, "pro")

    assert_equal File.join(@downloads, "dragonruby-pro-linux-amd64.zip"), path
    assert_equal @zip, File.binread(path)
    refute @server.requests.find { |p, _| p == "/files/engine.zip" }[1].key?("authorization"),
      "the login only goes to the API"
  end

  def test_fetch_handles_a_redirect_or_the_zip_itself
    assert_equal @zip, File.binread(fetcher.fetch(LOGIN, "indie"))

    @api_body = @zip
    assert_equal @zip, File.binread(fetcher.fetch(LOGIN, "pro"))
  end

  def test_fetch_rejects_unexpected_answers_and_cleans_up
    @api_body = "<html>Maintenance</html>"
    assert_raises(DrTalon::Error) { fetcher.fetch(LOGIN, "pro") }

    @api_body = @server.url("/files/not-a-zip")
    assert_raises(DrTalon::Error) { fetcher.fetch(LOGIN, "pro") }

    assert_empty Dir.children(@downloads)
  end

  def test_bad_logins
    anonymous = Fetcher.new(downloads_dir: @downloads, platform: "linux-amd64", api: @server.url("/api/download_%<tier>s_subscription_%<os>s"),
      http: DrTalon::HTTP.new.tap { |http| def http.download(url, path, auth: nil, &) = super(url, path, &) })

    assert_raises(DrTalon::HTTP::Unauthorized) { anonymous.fetch(LOGIN, "pro") }
    assert_raises(DrTalon::HTTP::Unauthorized) { anonymous.verify(LOGIN, "pro") }
  end

  def test_verify_does_not_download_the_engine
    fetcher.verify(LOGIN, "pro")

    assert_equal ["/api/download_pro_subscription_linux"], @server.requests.map(&:first)
    refute File.exist?(@downloads)
  end

  def test_butler_fetch
    butler = File.join(@dir, "butler")
    source = Dir.mktmpdir("butler-src", @dir)
    build_engine_dir(source)
    File.write(butler, "#!/bin/sh\n[ \"$1\" = fetch ] && [ \"$2\" = dragonruby/dragonruby-gtk:linux-amd64 ] && cp -R #{source}/. \"$3\"\n")
    File.chmod(0o755, butler)
    target = Dir.mktmpdir("target", @dir)

    DrTalon::Engine::ButlerFetcher.new(platform: "linux-amd64", butler: butler).fetch(target)

    assert DrTalon::Engine::Inspector.engine_root?(File.join(target, "dragonruby-linux-amd64"))
  end

  def test_butler_missing_or_failing
    error = assert_raises(DrTalon::Error) { DrTalon::Engine::ButlerFetcher.new(butler: File.join(@dir, "nope")).fetch(@dir) }
    assert_match(/butler, which isn't installed/, error.message)

    failing = File.join(@dir, "failing")
    File.write(failing, "#!/bin/sh\necho 'not logged in' >&2\nexit 1\n")
    File.chmod(0o755, failing)
    error = assert_raises(DrTalon::Error) { DrTalon::Engine::ButlerFetcher.new(butler: failing).fetch(@dir) }
    assert_match(/not logged in.*butler login/, error.message)
  end
end
