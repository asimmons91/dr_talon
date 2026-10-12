# frozen_string_literal: true

require "rbconfig"

module DrTalon
  # Resolves where talon keeps its global state: cached engines, downloads,
  # config and credentials.
  #
  # - Linux/BSD: XDG base directories (+XDG_DATA_HOME+, +XDG_CACHE_HOME+,
  #   +XDG_CONFIG_HOME+), defaulting to +~/.local/share+, +~/.cache+ and
  #   +~/.config+.
  # - macOS: +~/Library/Application Support+ and +~/Library/Caches+, unless
  #   the XDG variables are set explicitly.
  # - Windows: +%LOCALAPPDATA%+ for data and cache, +%APPDATA%+ for config.
  #
  # Setting +DR_TALON_HOME+ puts everything under that one directory, which is
  # handy for tests and for isolating experiments.
  class Paths
    APP_NAME = "dr_talon"

    # @param env [Hash{String => String}] environment to read overrides from
    # @param host_os [String] value of +RbConfig::CONFIG["host_os"]+
    # @param home [String] the user's home directory
    def initialize(env: ENV, host_os: RbConfig::CONFIG["host_os"], home: Dir.home)
      @env = env
      @platform = platform_for(host_os)
      @home = home
    end

    # @return [String] root for persistent data such as cached engines
    def data_dir
      @data_dir ||= resolve(:data)
    end

    # @return [String] root for disposable files such as downloaded zips
    def cache_dir
      @cache_dir ||= resolve(:cache)
    end

    # @return [String] root for user configuration
    def config_dir
      @config_dir ||= resolve(:config)
    end

    # @return [String] where unpacked engines are stored
    def engines_dir
      File.join(data_dir, "engines")
    end

    # @return [String] where downloaded engine zips are kept
    def downloads_dir
      File.join(cache_dir, "downloads")
    end

    # @return [String]
    def config_file
      File.join(config_dir, "config.yml")
    end

    # @return [String] dragonruby.org credentials, written with mode 0600
    def credentials_file
      File.join(config_dir, "credentials.yml")
    end

    private

    XDG_VARS = {data: "XDG_DATA_HOME", cache: "XDG_CACHE_HOME", config: "XDG_CONFIG_HOME"}.freeze
    XDG_DEFAULTS = {data: [".local", "share"], cache: [".cache"], config: [".config"]}.freeze

    def resolve(kind)
      if (root = present(@env["DR_TALON_HOME"]))
        return File.join(root, kind.to_s)
      end

      case @platform
      when :windows then windows_dir(kind)
      when :macos then present(@env[XDG_VARS[kind]]) ? xdg_dir(kind) : macos_dir(kind)
      else xdg_dir(kind)
      end
    end

    def xdg_dir(kind)
      base = present(@env[XDG_VARS[kind]]) || File.join(@home, *XDG_DEFAULTS[kind])
      File.join(base, APP_NAME)
    end

    def macos_dir(kind)
      base = (kind == :cache) ? "Caches" : "Application Support"
      File.join(@home, "Library", base, APP_NAME)
    end

    def windows_dir(kind)
      local = present(@env["LOCALAPPDATA"]) || File.join(@home, "AppData", "Local")
      roaming = present(@env["APPDATA"]) || File.join(@home, "AppData", "Roaming")

      case kind
      when :data then File.join(local, APP_NAME)
      when :cache then File.join(local, APP_NAME, "cache")
      when :config then File.join(roaming, APP_NAME)
      end
    end

    def platform_for(host_os)
      case host_os
      when /darwin/ then :macos
      when /mswin|mingw|cygwin/ then :windows
      else :unix
      end
    end

    def present(value)
      value unless value.nil? || value.empty?
    end
  end
end
