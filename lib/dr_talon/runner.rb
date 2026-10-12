# frozen_string_literal: true

module DrTalon
  # Builds and runs the commands of a project's installed engine:
  # +dragonruby+, +dragonruby-publish+ and +dragonruby-httpd+.
  class Runner
    # The project doesn't have the needed engine binary installed.
    class MissingBinary < Error; end

    # DragonRuby writes these while running and building.
    GENERATED_DIRS = %w[builds logs tmp errors].freeze

    TEST_PATTERN = "*_tests.rb"
    TEST_DIRS = %w[test tests].freeze

    # Environment for running without a window, e.g. in CI.
    HEADLESS_ENV = {"SDL_VIDEO_DRIVER" => "dummy", "SDL_AUDIO_DRIVER" => "dummy"}.freeze

    # Replaces the current process. Separate so tests can stub it.
    #
    # @param argv [Array<String>]
    # @param chdir [String]
    def self.exec_process(argv, chdir:)
      Process.exec(*argv, chdir: chdir)
    end

    # @param project [Project]
    def initialize(project)
      @project = project
    end

    # @param name [String]
    # @return [String] absolute path to the binary in the project root
    # @raise [MissingBinary]
    def binary(name = "dragonruby")
      path = [name, "#{name}.exe"].map { |candidate| @project.path(candidate) }.find { |p| File.file?(p) }
      return path if path

      hint =
        if name != "dragonruby" && @project.layout == :game_only
          "Game-only projects only get the dragonruby binary; build and serve need DragonRuby's full layout."
        else
          "Install the engine with `talon engine use`."
        end
      raise MissingBinary, "No #{name} in #{@project.root}. #{hint}"
    end

    # @return [String] the game directory as +dragonruby+ expects it
    def game_arg
      (@project.layout == :game_only) ? "." : "mygame"
    end

    # @param args [Array<String>] passed through, e.g. --record
    # @return [Array<String>]
    def run_command(args = [])
      [binary, game_arg, *args]
    end

    # Packages every platform into builds/ without uploading.
    #
    # @param args [Array<String>] passed through to dragonruby-publish
    # @return [Array<String>]
    def build_command(args = [])
      [binary("dragonruby-publish"), "--only-package", *args, game_arg]
    end

    # @param dir [String] directory to serve
    # @param port [Integer]
    # @return [Array<String>]
    def serve_command(dir, port)
      [binary("dragonruby-httpd"), dir, port.to_s]
    end

    # @param file [String] relative to the game directory
    # @return [Array<String>]
    def test_command(file)
      [binary, game_arg, "--test", file]
    end

    # @return [String, nil] the newest HTML5 build, relative to the project root
    def html5_build
      Dir.glob("builds/*-html5-*/", base: @project.root)
        .select { |dir| File.file?(@project.path(dir, "index.html")) }
        .max_by { |dir| File.mtime(@project.path(dir)) }
        &.chomp("/")
    end

    # Test files to run, relative to the game directory.
    #
    # @param paths [Array<String>] files or directories, relative to +base+;
    #   all of test/ and tests/ when empty
    # @param base [String] what +paths+ are relative to (the working directory)
    # @return [Array<String>]
    # @raise [Error] if a path is missing or outside the game directory
    def test_files(paths = [], base: Dir.pwd)
      game_dir = File.expand_path(@project.game_dir)

      files =
        if paths.empty?
          TEST_DIRS.flat_map { |dir| Dir.glob(File.join(dir, "**", TEST_PATTERN), base: game_dir) }
        else
          paths.flat_map { |path| expand_test_path(File.expand_path(path, base), game_dir) }
        end

      files.uniq.sort
    end

    # Runs one test file and reads the outcome from DragonRuby's output.
    #
    # @param file [String] relative to the game directory
    # @param timeout [Numeric] seconds before the run is killed
    # @param headless [Boolean] run without a window
    # @return [TestReport]
    def run_test(file, timeout: 120, headless: true)
      env = headless ? HEADLESS_ENV.reject { |key, _| ENV.key?(key) } : {}
      reader, writer = IO.pipe
      # Its own process group, so a timeout can stop anything it started that
      # still holds the output pipe open.
      group = Gem.win_platform? ? {new_pgroup: true} : {pgroup: true}
      pid = Process.spawn(env, *test_command(file), chdir: @project.root, out: writer, err: writer, in: File::NULL, **group)
      writer.close
      output = Thread.new { reader.read }

      exited = wait(pid, timeout)
      stop(pid) unless exited
      report = exited ? TestReport.parse(output.value) : TestReport.timeout(output.value)
      pid = nil
      report
    ensure
      # Interrupted (e.g. Ctrl-C, which the separate process group doesn't
      # receive) or failed: don't leave DragonRuby running.
      stop(pid) if pid
      writer&.close unless writer&.closed?
      reader&.close
    end

    # Deletes what DragonRuby generates while running and building.
    #
    # @return [Array<String>] removed paths, relative to the project root
    def clean
      dirs = GENERATED_DIRS.dup
      dirs += GENERATED_DIRS.map { |dir| "mygame/#{dir}" } if @project.layout == :full

      dirs.select { |dir| File.directory?(@project.path(dir)) }.each do |dir|
        FileUtils.rm_rf(@project.path(dir))
      end
    end

    private

    def expand_test_path(path, game_dir)
      unless path == game_dir || path.start_with?(game_dir + File::SEPARATOR)
        raise Error, "#{path} is outside the game directory (#{game_dir})."
      end

      relative = path.delete_prefix(game_dir).delete_prefix(File::SEPARATOR)
      if File.directory?(path)
        Dir.glob(File.join("**", TEST_PATTERN), base: path).map { |file| relative.empty? ? file : File.join(relative, file) }
      elsif File.file?(path)
        [relative]
      else
        raise Error, "#{path} doesn't exist."
      end
    end

    # @return [Boolean] whether the process exited before the timeout
    def wait(pid, timeout)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        return true if Process.waitpid(pid, Process::WNOHANG)
        return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.05
      end
    end

    def stop(pid)
      target = Gem.win_platform? ? pid : -pid
      Process.kill(:TERM, target)
      return if wait(pid, 5)

      Process.kill(:KILL, target)
      Process.waitpid(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  end
end
