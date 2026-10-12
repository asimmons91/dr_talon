# frozen_string_literal: true

require "test_helper"

class TestEngineFetchers < Minitest::Test
  include EngineFixtures

  Fetchers = DrTalon::Engine::Fetchers
  LOGIN = DrTalon::Credentials.new(username: "me", password: "pw", source: :env)

  # The demo section of DragonRuby's itch.io page, with attributes in a
  # different order per upload, as itch.io does.
  ITCH_PAGE = <<~HTML
    <html><head><meta name="csrf_token" value="TOKEN123" /></head><body>
    <div class="uploads"><div class="upload"><a class="button" data-upload_id="1">Download</a>
      <strong class="name" title="x64 Linux Standard License">x64 Linux Standard License</strong></div></div>
    <div class="uploads for_demo has_buttons"><div id="w" class="upload_list_widget base_widget">
      <div class="upload"><a data-upload_id="101" href="#" class="button download_btn">Download</a>
        <div class="upload_name"><strong title="macOS Jam License" class="name">macOS Jam License</strong></div></div>
      <div class="upload"><a href="#" class="button download_btn" data-upload_id="102">Download</a>
        <div class="upload_name"><strong class="name" title="x64 Linux Jam License">x64 Linux Jam License</strong></div></div>
      <div class="upload"><a data-upload_id="103" class="button download_btn">Download</a>
        <div class="upload_name"><strong title="arm64 Linux Jam License" class="name">arm64</strong></div></div>
    </div></div>
    <section id="devlog"></section></body></html>
  HTML

  def setup
    @dir = Dir.mktmpdir
    @zip = File.binread(build_engine_zip(@dir))
    @api_body = nil
    @itch_page = ITCH_PAGE
    @server = TestServer.new(
      "/api/download_pro_subscription_linux" => lambda do |headers|
        next [401, {}, "HTTP Basic: Access denied.\n"] unless headers["authorization"]

        [200, {}, @api_body || @server.url("/files/engine.zip")]
      end,
      "/api/download_indie_subscription_linux" => ->(_) { [302, {"Location" => "/files/engine.zip"}, ""] },
      "/files/engine.zip" => ->(_) { [200, {}, @zip] },
      "/files/not-a-zip" => ->(_) { [200, {}, "<html>"] },
      "/game" => ->(_) { [200, {}, @itch_page] },
      "/game/file/102" => lambda do |_headers, body|
        next [200, {}, %({"lightbox": {}})] unless body.include?("csrf_token=TOKEN123")

        [200, {"Content-Type" => "application/json"}, JSON.generate("url" => @server.url("/files/engine.zip"), "external" => false)]
      end
    )
    @downloads = File.join(@dir, "downloads")
  end

  def teardown
    @server.stop
    FileUtils.rm_rf(@dir)
  end

  def api(tier = "pro", platform: "linux-amd64", **options)
    Fetchers::DragonRubyAPI.new(tier, downloads_dir: @downloads, platform: platform,
      api: @server.url("/api/download_%<tier>s_subscription_%<os>s"), **options)
  end

  def jam(platform: "linux-amd64")
    Fetchers::ItchJam.new(downloads_dir: @downloads, platform: platform, page: @server.url("/game"))
  end

  def test_for_picks_a_fetcher_per_tier
    assert_instance_of Fetchers::DragonRubyAPI, Fetchers.for("pro")
    assert_equal "indie", Fetchers.for("indie").tier
    assert_instance_of Fetchers::ItchJam, Fetchers.for("jam")
    assert_instance_of Fetchers::Butler, Fetchers.for("standard")
    assert_raises(DrTalon::Error) { Fetchers.for("gold") }
    assert Fetchers.for("pro").credentials?
    refute Fetchers.for("jam").credentials?
  end

  def test_api_urls_per_platform
    real = ->(platform) { Fetchers::DragonRubyAPI.new("pro", platform: platform, downloads_dir: @downloads).api_url }

    assert_equal "https://dragonruby.org/api/download_pro_subscription_linux", real.call("linux-amd64")
    assert_equal "https://dragonruby.org/api/download_pro_subscription_mac", real.call("macos")
    assert_equal "https://dragonruby.org/api/download_pro_subscription_windows", real.call("windows-amd64")
    assert_raises(DrTalon::Error) { real.call("linux-arm64") }
  end

  def test_api_fetch_follows_the_url_in_the_body
    path = api.fetch(credentials: LOGIN)

    assert_equal File.join(@downloads, "dragonruby-pro-linux-amd64.zip"), path
    assert_equal @zip, File.binread(path)
    refute @server.requests.find { |p, _| p == "/files/engine.zip" }[1].key?("authorization"),
      "the login only goes to the API"
  end

  def test_api_fetch_handles_a_redirect_or_the_zip_itself
    assert_equal @zip, File.binread(api("indie").fetch(credentials: LOGIN))

    @api_body = @zip
    assert_equal @zip, File.binread(api.fetch(credentials: LOGIN))
  end

  def test_api_fetch_rejects_unexpected_answers_and_cleans_up
    @api_body = "<html>Maintenance</html>"
    assert_raises(DrTalon::Error) { api.fetch(credentials: LOGIN) }

    @api_body = @server.url("/files/not-a-zip")
    assert_raises(DrTalon::Error) { api.fetch(credentials: LOGIN) }

    assert_empty Dir.children(@downloads)
  end

  def test_api_needs_a_login
    assert_raises(DrTalon::Error) { api.fetch(credentials: nil) }

    anonymous = api(http: DrTalon::HTTP.new.tap { |http| def http.download(url, path, auth: nil, &) = super(url, path, &) })
    assert_raises(DrTalon::HTTP::Unauthorized) { anonymous.fetch(credentials: LOGIN) }
    assert_raises(DrTalon::HTTP::Unauthorized) { anonymous.verify(LOGIN) }
  end

  def test_api_verify_does_not_download_the_engine
    api.verify(LOGIN)

    assert_equal ["/api/download_pro_subscription_linux"], @server.requests.map(&:first)
    refute File.exist?(@downloads)
  end

  def test_jam_fetches_the_demo_upload_for_the_platform
    path = jam.fetch

    assert_equal File.join(@downloads, "dragonruby-gtk-linux-amd64-jam.zip"), path
    assert_equal @zip, File.binread(path)
    post = @server.requests.find { |_, _, method| method == "POST" }
    assert post.first.start_with?("/game/file/102?"), "the x64 Linux upload, not the paid one or another platform"
    assert_includes post[3], "csrf_token=TOKEN123"
    refute @server.requests.any? { |_, headers| headers.key?("authorization") }, "no login is sent"
  end

  def test_jam_without_an_upload_for_the_platform
    assert_raises(DrTalon::Error) { jam(platform: "windows-amd64").fetch } # not on the test page
    assert_raises(DrTalon::Error) { jam(platform: "beos").fetch }
  end

  def test_jam_when_the_page_changes
    @itch_page = "<html>redesigned</html>"

    error = assert_raises(DrTalon::Error) { jam.fetch }
    assert_match(/page may have changed.*talon engine import/, error.message)
  end

  def test_jam_without_a_token_gets_no_link
    @itch_page = ITCH_PAGE.sub("TOKEN123", "WRONG")

    error = assert_raises(DrTalon::Error) { jam.fetch }
    assert_match(/didn't return a download link/, error.message)
    refute File.exist?(File.join(@downloads, "dragonruby-gtk-linux-amd64-jam.zip"))
  end

  def test_butler_fetch
    butler = File.join(@dir, "butler")
    source = Dir.mktmpdir("butler-src", @dir)
    build_engine_dir(source)
    File.write(butler, "#!/bin/sh\n[ \"$1\" = fetch ] && [ \"$2\" = dragonruby/dragonruby-gtk:linux-amd64 ] && cp -R #{source}/. \"$3\"\n")
    File.chmod(0o755, butler)

    dir = Fetchers::Butler.new(platform: "linux-amd64", downloads_dir: @downloads, butler: butler).fetch

    assert DrTalon::Engine::Inspector.engine_root?(File.join(dir, "dragonruby-linux-amd64"))
    assert dir.start_with?(@downloads)
  end

  def test_butler_missing_or_failing_cleans_up
    error = assert_raises(DrTalon::Error) { Fetchers::Butler.new(downloads_dir: @downloads, butler: File.join(@dir, "nope")).fetch }
    assert_match(/butler, which isn't installed.*--tier jam/, error.message)

    failing = File.join(@dir, "failing")
    File.write(failing, "#!/bin/sh\necho 'not logged in' >&2\nexit 1\n")
    File.chmod(0o755, failing)
    error = assert_raises(DrTalon::Error) { Fetchers::Butler.new(downloads_dir: @downloads, butler: failing).fetch }
    assert_match(/not logged in.*butler login/, error.message)

    assert_empty Dir.children(@downloads)
  end
end
