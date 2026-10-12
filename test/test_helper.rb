# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "dr_talon"

require "fileutils"
require "tmpdir"
require "minitest/autorun"

# Thor prompts through Readline when it can load it (Ruby before 4.0), and
# Readline reads the real STDIN. Tests feed answers through $stdin, which
# Thor's basic editor reads on every Ruby.
Thor::LineEditor.singleton_class.prepend(Module.new { def best_available = Thor::LineEditor::Basic })
require "open3"
require "socket"

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

# Local git repositories standing in for GitHub and other remotes, plus a
# fake HTTP client that serves GitHub-style tarballs and plain files.
module DepsFixtures
  GIT_ENV = {
    "GIT_AUTHOR_NAME" => "Test", "GIT_AUTHOR_EMAIL" => "test@example.com",
    "GIT_COMMITTER_NAME" => "Test", "GIT_COMMITTER_EMAIL" => "test@example.com",
    "GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_SYSTEM" => File::NULL
  }.freeze

  # Serves "#{codeload}/OWNER/REPO/tar.gz/SHA" from the matching fixture
  # repository and any other URL from +files+; counts requests.
  class FakeHTTP
    attr_reader :requests, :files

    def initialize(remotes)
      @remotes = remotes
      @files = {}
      @requests = []
    end

    def get(url)
      @requests << url
      if (match = %r{\Afake-codeload://([^/]+)/([^/]+)/tar\.gz/(\h{40})\z}.match(url))
        owner, repo, sha = match.captures
        out, status = Open3.capture2("git", "-C", File.join(@remotes, owner, "#{repo}.git"),
          "archive", "--format=tar.gz", "--prefix=#{repo}-#{sha}/", sha, binmode: true)
        raise DrTalon::Deps::FetchError, "no such commit" unless status.success?

        out
      else
        @files.fetch(url) { raise DrTalon::Deps::FetchError, "GET #{url} returned 404 Not Found" }
      end
    end
  end

  def git!(dir, *args)
    out, err, status = Open3.capture3(GIT_ENV, "git", "-C", dir, *args)
    raise "git #{args.join(" ")} failed: #{err}" unless status.success?

    out.strip
  end

  # Creates (or adds a commit to) a repository at remotes/OWNER/REPO.git.
  #
  # @return [String] the new commit's SHA
  def commit_to(remotes, owner, repo, files, tag: nil)
    path = File.join(remotes, owner, "#{repo}.git")
    unless File.directory?(path)
      FileUtils.mkdir_p(path)
      git!(path, "init", "--quiet", "--initial-branch=main")
    end
    files.each do |relative, content|
      FileUtils.mkdir_p(File.dirname(File.join(path, relative)))
      File.write(File.join(path, relative), content)
    end
    git!(path, "add", "--all")
    git!(path, "commit", "--quiet", "--message", "commit")
    git!(path, "tag", "--annotate", tag, "--message", tag) if tag
    git!(path, "rev-parse", "HEAD")
  end

  def deps_context(remotes)
    DrTalon::Deps::Context.new(
      http: FakeHTTP.new(remotes), git: DrTalon::Deps::Git.new,
      github_url: "file://#{remotes}", codeload_url: "fake-codeload:/"
    )
  end
end

# A tiny HTTP/1.1 server for HTTP client tests. Routes map a path (without
# the query) to a lambda receiving (headers) or (headers, request_body) and
# returning [status, headers, body]. Requests are recorded as
# [path_with_query, headers, method, body].
class TestServer
  attr_reader :port, :requests

  def initialize(routes)
    @routes = routes
    @requests = []
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new { serve }
  end

  def url(path, host: "127.0.0.1")
    "http://#{host}:#{port}#{path}"
  end

  def stop
    @thread.kill
    @server.close
  end

  private

  def serve
    loop do
      client = @server.accept
      request_line = client.gets.to_s
      headers = {}
      while (line = client.gets) && line != "\r\n"
        name, value = line.split(":", 2)
        headers[name.downcase] = value.strip
      end
      method, path = request_line.split
      body = headers["content-length"] ? client.read(headers["content-length"].to_i) : ""
      @requests << [path, headers, method, body]
      route = @routes.fetch(path.split("?").first, ->(_) { [404, {}, "not found"] })
      status, response_headers, body = (route.arity == 2) ? route.call(headers, body) : route.call(headers)
      client.write("HTTP/1.1 #{status} X\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n")
      response_headers.each { |name, value| client.write("#{name}: #{value}\r\n") }
      client.write("\r\n#{body}")
      client.close
    end
  rescue IOError, Errno::EBADF
    nil
  end
end
