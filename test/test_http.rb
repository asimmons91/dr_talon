# frozen_string_literal: true

require "test_helper"

class TestHTTP < Minitest::Test
  AUTH = DrTalon::HTTP::Auth.new(username: "user", password: "secret")

  def setup
    @dir = Dir.mktmpdir
    @server = TestServer.new(
      "/file" => ->(_) { [200, {}, "hello"] },
      "/redirect" => ->(_) { [302, {"Location" => "/file"}, ""] },
      "/other-host" => ->(_) { [302, {"Location" => @server.url("/echo-auth", host: "localhost")}, ""] },
      "/echo-auth" => ->(headers) { [200, {}, headers["authorization"].to_s] },
      "/secret" => ->(headers) { headers["authorization"] ? [200, {}, "ok"] : [401, {}, "denied"] },
      "/loop" => ->(_) { [302, {"Location" => "/loop"}, ""] },
      "/broken" => ->(_) { [500, {}, "oops"] }
    )
    @http = DrTalon::HTTP.new
  end

  def teardown
    @server.stop
    FileUtils.rm_rf(@dir)
  end

  def test_get_follows_redirects
    assert_equal "hello", @http.get(@server.url("/redirect"))
  end

  def test_basic_auth_goes_to_the_original_host_only
    assert_match(/\ABasic /, @http.get(@server.url("/echo-auth"), auth: AUTH))
    assert_equal "", @http.get(@server.url("/other-host"), auth: AUTH)
  end

  def test_unauthorized
    assert_raises(DrTalon::HTTP::Unauthorized) { @http.get(@server.url("/secret")) }
    assert_equal "ok", @http.get(@server.url("/secret"), auth: AUTH)
  end

  def test_errors
    assert_raises(DrTalon::HTTP::Error) { @http.get(@server.url("/broken")) }
    assert_raises(DrTalon::HTTP::Error) { @http.get(@server.url("/missing")) }
    error = assert_raises(DrTalon::HTTP::Error) { @http.get(@server.url("/loop")) }
    assert_match(/redirected more than/, error.message)
    assert_raises(DrTalon::HTTP::Error) { @http.get("ftp://example.com/x") }
  end

  def test_download_streams_to_a_file_with_progress
    path = File.join(@dir, "out")
    progress = []

    result = @http.download(@server.url("/redirect"), path) { |received, total| progress << [received, total] }

    assert_equal path, result
    assert_equal "hello", File.read(path)
    assert_equal [5, 5], progress.last
  end
end
