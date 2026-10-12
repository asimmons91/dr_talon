# frozen_string_literal: true

module DrTalon
  # A DragonRuby game (or library) directory managed by talon.
  #
  # Two layouts are supported:
  # - +:full+, DragonRuby's own: engine files at the root, game in +mygame/+
  # - +:game_only+: the root is the game directory (+app/main.rb+), as used
  #   by libraries; only the engine binary and font sit beside it
  class Project
    PIN_FILE = ".dragonruby-version"

    # No project at or above the working directory.
    class NotFound < Error; end

    # Walks up from +dir+ to the nearest directory with a {PIN_FILE}.
    #
    # @param dir [String]
    # @return [Project, nil]
    def self.find(dir = Dir.pwd)
      dir = File.expand_path(dir)

      loop do
        return new(dir) if File.file?(File.join(dir, PIN_FILE))

        parent = File.dirname(dir)
        return nil if parent == dir

        dir = parent
      end
    end

    # The pinned project at or above +dir+, or else +dir+ itself when it
    # looks like a DragonRuby game. Refuses other directories so engine files
    # never get copied somewhere unexpected, such as a home directory.
    #
    # @param dir [String]
    # @return [Project]
    # @raise [NotFound]
    def self.locate(dir = Dir.pwd)
      project = find(dir) || new(File.expand_path(dir))
      return project if project.layout

      raise NotFound, "#{project.root} doesn't look like a DragonRuby project " \
        "(no #{PIN_FILE}, mygame/app/main.rb or app/main.rb)."
    end

    # @return [String]
    attr_reader :root

    # @param root [String]
    def initialize(root)
      @root = root
    end

    # @return [Symbol, nil] +:full+, +:game_only+, or nil if neither fits
    def layout
      if File.file?(File.join(root, "mygame", "app", "main.rb"))
        :full
      elsif File.file?(File.join(root, "app", "main.rb"))
        :game_only
      end
    end

    # @return [String] the directory passed to +dragonruby+
    def game_dir
      (layout == :game_only) ? root : File.join(root, "mygame")
    end

    # @return [String]
    def pin_path
      File.join(root, PIN_FILE)
    end

    # @return [Engine::Spec, nil] the pinned engine, without a platform
    # @raise [Error] if the pin file can't be parsed
    def pin
      return nil unless File.file?(pin_path)

      line = File.readlines(pin_path, chomp: true).map(&:strip).find { |l| !l.empty? && !l.start_with?("#") }
      raise Error, "#{PIN_FILE} is empty." unless line

      Engine::Spec.parse(line)
    end

    # Pins +installation+'s version and tier. The platform is left out so the
    # pin works on every developer's machine.
    #
    # @param installation [Engine::Installation]
    # @return [void]
    def pin!(installation)
      File.write(pin_path, "#{installation.version}-#{installation.tier}\n")
    end

    # @param relative [String]
    # @return [String]
    def path(*relative)
      File.join(root, *relative)
    end
  end
end
