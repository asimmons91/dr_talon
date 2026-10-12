# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "dr_talon"

require "fileutils"
require "tmpdir"
require "minitest/autorun"

# Builds tiny stand-ins for DragonRuby distributions, with the files talon
# inspects and an executable "binary", so tests never need the real engine.
module EngineFixtures
  BUILD_DATE = "Wed Oct 7 22:19:14 CDT 2026"
  GIT_SHA = "0c37cf3bb50cff40b47bc6b935bdd106e47aebada"

  # @return [String] the engine root, +parent/dragonruby-<platform>+
  def build_engine_dir(parent, version: "7.23", platform: "linux-amd64", binary: "dragonruby")
    root = File.join(parent, "dragonruby-#{platform}")
    FileUtils.mkdir_p(File.join(root, ".dragonruby", "stubs"))
    FileUtils.mkdir_p(File.join(root, "mygame", "app"))

    File.write(File.join(root, "CHANGELOG-CURR.txt"), "* #{version}\n** [Bugfix] Something.\n* 7.1\n** Older.\n")
    File.write(File.join(root, "VERSION.txt"), "date: #{BUILD_DATE}\ngit: #{GIT_SHA}\n")
    File.write(File.join(root, binary), "#!/bin/sh\necho dragonruby #{version}\n")
    File.chmod(0o755, File.join(root, binary))
    File.write(File.join(root, ".dragonruby", "stubs", "linux-amd64"), "stub")
    File.write(File.join(root, "mygame", "app", "main.rb"), "def tick(args); end\n")

    root
  end

  # @return [String] path to a zip laid out like DragonRuby's downloads
  def build_engine_zip(dir, name: "dragonruby-pro-linux-amd64.zip", **engine_options)
    source = Dir.mktmpdir("engine-src", dir)
    build_engine_dir(source, **engine_options)

    path = File.join(dir, name)
    Zip::File.open(path, create: true) do |zip|
      Dir.glob("**/*", File::FNM_DOTMATCH, base: source).sort.each do |relative|
        next if File.basename(relative) == "."

        full = File.join(source, relative)
        File.directory?(full) ? zip.mkdir(relative) : zip.add(relative, full)
      end
    end
    path
  end
end
