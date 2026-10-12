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

  # The publishing section of DragonRuby's stock game_metadata.txt.
  STOCK_METADATA = <<~TXT
    # === Remove the pound sign and leading space for the properties below before publishing your game. ===
    # devid=your_itchio_username
    # devtitle=Your Itch.io Display Name
    # gameid=your_itchio_game_id
    # gametitle=Your Game Title
    # version=0.1
    # icon=metadata/icon.png

    orientation=landscape
  TXT

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
    FileUtils.mkdir_p(File.join(root, "mygame", "metadata"))
    File.write(File.join(root, "mygame", "metadata", "game_metadata.txt"), STOCK_METADATA)

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

  # Imports a fixture engine into +store+ and returns the installation.
  def import_engine(store, dir, version: "7.23", tier: "pro", platform: "linux-amd64", &customize)
    parent = Dir.mktmpdir("engine", dir)
    root = build_engine_dir(parent, version: version, platform: platform)
    customize&.call(root)
    DrTalon::Engine::Importer.new(store, tier: tier).import(root).installation
  end

  # @return [String] a project directory with a game in the given layout
  def build_project(dir, layout: :full)
    root = Dir.mktmpdir("project", dir)
    game = (layout == :full) ? File.join(root, "mygame") : root
    FileUtils.mkdir_p(File.join(game, "app"))
    File.write(File.join(game, "app", "main.rb"), "def tick(args); end\n")
    root
  end

  # Replaces the project's dragonruby with a script that prints the
  # "<test file minus .rb>.out" fixture next to the requested test file and
  # records its arguments and SDL environment in args.log.
  def install_fake_dragonruby(root, game_arg: "mygame")
    script = <<~SH
      #!/bin/sh
      echo "$@ SDL_VIDEO_DRIVER=$SDL_VIDEO_DRIVER" >> args.log
      if [ "$2" = "--test" ]; then
        case "$3" in
          *sleep*) sleep 5 ;;
          *) cat "$1/${3%.rb}.out" ;;
        esac
      fi
    SH
    path = File.join(root, "dragonruby")
    File.write(path, script)
    File.chmod(0o755, path)
    game_arg
  end

  # @return [String] the contents of a real DragonRuby output fixture
  def dragonruby_output(name)
    File.read(File.join(__dir__, "fixtures", "dragonruby", "#{name}.log"))
  end
end
