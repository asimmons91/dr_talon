# frozen_string_literal: true

require "test_helper"

class TestPaths < Minitest::Test
  HOME = "/home/dev"

  def paths(host_os: "linux-gnu", **env)
    DrTalon::Paths.new(env: env.transform_keys(&:to_s), host_os: host_os, home: HOME)
  end

  def test_linux_defaults_follow_xdg
    p = paths

    assert_equal "/home/dev/.local/share/dr_talon", p.data_dir
    assert_equal "/home/dev/.cache/dr_talon", p.cache_dir
    assert_equal "/home/dev/.config/dr_talon", p.config_dir
  end

  def test_linux_honors_xdg_variables
    p = paths(XDG_DATA_HOME: "/xdg/data", XDG_CACHE_HOME: "/xdg/cache", XDG_CONFIG_HOME: "/xdg/config")

    assert_equal "/xdg/data/dr_talon", p.data_dir
    assert_equal "/xdg/cache/dr_talon", p.cache_dir
    assert_equal "/xdg/config/dr_talon", p.config_dir
  end

  def test_empty_xdg_variables_are_ignored
    assert_equal "/home/dev/.local/share/dr_talon", paths(XDG_DATA_HOME: "").data_dir
  end

  def test_macos_defaults_to_library
    p = paths(host_os: "darwin24")

    assert_equal "/home/dev/Library/Application Support/dr_talon", p.data_dir
    assert_equal "/home/dev/Library/Caches/dr_talon", p.cache_dir
    assert_equal "/home/dev/Library/Application Support/dr_talon", p.config_dir
  end

  def test_macos_honors_explicit_xdg_variables
    assert_equal "/xdg/config/dr_talon", paths(host_os: "darwin24", XDG_CONFIG_HOME: "/xdg/config").config_dir
  end

  def test_windows_uses_appdata
    p = paths(host_os: "mingw32", LOCALAPPDATA: "C:/Users/dev/AppData/Local", APPDATA: "C:/Users/dev/AppData/Roaming")

    assert_equal "C:/Users/dev/AppData/Local/dr_talon", p.data_dir
    assert_equal "C:/Users/dev/AppData/Local/dr_talon/cache", p.cache_dir
    assert_equal "C:/Users/dev/AppData/Roaming/dr_talon", p.config_dir
  end

  def test_dr_talon_home_overrides_everything
    p = paths(host_os: "darwin24", DR_TALON_HOME: "/tmp/talon", XDG_DATA_HOME: "/xdg/data")

    assert_equal "/tmp/talon/data", p.data_dir
    assert_equal "/tmp/talon/cache", p.cache_dir
    assert_equal "/tmp/talon/config", p.config_dir
  end

  def test_derived_locations
    p = paths

    assert_equal "/home/dev/.local/share/dr_talon/engines", p.engines_dir
    assert_equal "/home/dev/.cache/dr_talon/downloads", p.downloads_dir
    assert_equal "/home/dev/.config/dr_talon/config.yml", p.config_file
    assert_equal "/home/dev/.config/dr_talon/credentials.yml", p.credentials_file
  end
end
