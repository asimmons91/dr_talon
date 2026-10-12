# frozen_string_literal: true

module DrTalon
  module Deps
    # One pinned dependency, stored as a tab-separated line below +__END__+:
    #
    #   key  ref  destination  commit  checksum
    #
    # +ref+ and +commit+ are "-" when absent; +checksum+ covers the vendored
    # files so local edits can be detected.
    Lock = Data.define(:key, :ref, :destination, :commit, :checksum) do
      def self.parse(line)
        fields = line.split("\t").map { |field| (field == "-") ? nil : field }
        new(*fields) if fields.size == members.size
      end

      def to_line
        to_a.map { |field| field || "-" }.join("\t")
      end

      def to_a
        [key, ref, destination, commit, checksum]
      end
    end

    # +dependencies.rb+ in the game directory: a Ruby DSL above +__END__+,
    # owned by the user, and lock lines below it, owned by talon. The DSL is
    # compatible with Foodchain's (+github :owner, :repo, "path", destination:+).
    class Manifest
      FILE = "dependencies.rb"
      SEPARATOR = /^__END__\r?\n?/
      LOCK_HEADER = <<~TEXT
        # The lines below pin the versions of your installed dependencies.
        # Managed by `talon install` / `talon update`; do not edit by hand.
      TEXT

      # @return [String]
      attr_reader :path
      # @return [String] everything above __END__
      attr_reader :config
      # @return [Array<Dependency>]
      attr_reader :dependencies
      # @return [Array<Lock>]
      attr_reader :locks
      # @return [Boolean] whether the lock section had Foodchain's ETag lines
      attr_reader :foodchain_locks

      # @param project [Project]
      # @return [Manifest]
      def self.for(project)
        new(File.join(project.game_dir, FILE))
      end

      # @param path [String] need not exist yet
      # @raise [ManifestError] if the DSL is invalid
      def initialize(path)
        @path = path
        content = File.file?(path) ? File.read(path) : ""
        config, separator, locks = content.partition(SEPARATOR)
        @config = config
        @had_separator = !separator.empty?
        @locks, @foodchain_locks = parse_locks(locks)
        @dependencies = DSL.evaluate(config, path)
      end

      # @return [Boolean]
      def exist?
        File.file?(path)
      end

      # @param name [String] a dependency's name or key
      # @return [Dependency, nil]
      def find(name)
        dependencies.find { |dependency| dependency.name == name || dependency.key == name }
      end

      # Rewrites the lock section, keeping everything above __END__ as is.
      #
      # @param locks [Array<Lock>]
      # @return [void]
      def write_locks(locks)
        @locks = locks.sort_by(&:key)
        body = [config.rstrip, "", "__END__", "", LOCK_HEADER, *@locks.map(&:to_line)].join("\n")
        File.write(path, body.sub(/\A\n+/, "") + "\n")
      end

      # Appends a declaration to the DSL section and checks it parses.
      #
      # @param line [String]
      # @return [void]
      # @raise [ManifestError] (leaving the file unchanged) if it doesn't
      def add(line)
        update_config(config.rstrip.then { |c| c.empty? ? "#{line}\n" : "#{c}\n#{line}\n" })
      end

      # Deletes +dependency+'s declaration from the DSL section.
      #
      # @param dependency [Dependency]
      # @return [void]
      # @raise [ManifestError] if the declaration spans several lines
      def remove(dependency)
        lines = config.lines
        index = dependency.line && dependency.line - 1
        text = index && lines[index]
        declares = text && DSL::METHODS.any? { |method| text.lstrip.start_with?("#{method} ", "#{method}(") }
        continues = text&.rstrip&.end_with?(",", "\\", "(")
        unless declares && !continues
          raise ManifestError, "Can't remove #{dependency.name} automatically; edit #{FILE} by hand."
        end

        lines.delete_at(index)
        update_config(lines.join)
      end

      private

      # Validates before writing, so a bad edit leaves the file alone.
      def update_config(new_config)
        @dependencies = DSL.evaluate(new_config, path)
        @config = new_config
        write_locks(locks)
      end

      # Foodchain's two-column ETag lines can't be reused; they're dropped and
      # the dependencies re-resolved.
      def parse_locks(text)
        lines = text.lines(chomp: true).reject { |line| line.strip.empty? || line.start_with?("#") }
        locks = lines.filter_map { |line| Lock.parse(line) }
        [locks, locks.size < lines.size]
      end
    end

    # Evaluates the DSL section of +dependencies.rb+.
    class DSL
      METHODS = %w[github git url path].freeze

      # @param source [String]
      # @param file [String] for line numbers in errors
      # @return [Array<Dependency>]
      # @raise [ManifestError]
      def self.evaluate(source, file)
        dsl = new(file)
        dsl.instance_eval(source, file, 1)
        dsl.dependencies
      rescue ManifestError
        raise
      rescue ScriptError, StandardError => e
        location = e.backtrace_locations&.find { |l| l.path == file }&.lineno
        raise ManifestError, "#{File.basename(file)}#{":#{location}" if location}: #{e.message}"
      end

      attr_reader :dependencies

      def initialize(file)
        @file = file
        @dependencies = []
      end

      # Foodchain files start with `require "vendor/foodchain"`; requires
      # don't mean anything to talon.
      def require(*)
        nil
      end

      # github "owner/repo", path: "lib", ref: "v1.0", as: "name"
      # github :owner, :repo, "lib", ref: "v1.0", destination: "vendor/name"  (Foodchain)
      def github(*args, path: nil, ref: nil, as: nil, destination: nil)
        owner, repo, positional_path =
          case args.size
          when 1 then [*args.first.to_s.split("/", 2), nil]
          when 2, 3 then args
          else raise ArgumentError, "github expects \"owner/repo\" or owner, repo[, path]"
          end
        raise ArgumentError, "github needs \"owner/repo\"" if owner.to_s.empty? || repo.to_s.empty?

        add(GitHubDependency, owner, repo, subpath: path || positional_path, ref: ref, as: as, destination: destination)
      end

      # git "https://host/repo.git", path: "lib", ref: "main", as: "name"
      def git(url, path: nil, ref: nil, as: nil, destination: nil)
        add(GitDependency, url, subpath: path, ref: ref, as: as, destination: destination)
      end

      # url "https://example.com/tween.rb", as: "tween.rb"
      def url(url, as: nil, destination: nil)
        add(URLDependency, url, as: as, destination: destination)
      end

      # path "../my_library/lib", as: "my_library"
      def path(dir, as: nil, destination: nil)
        add(PathDependency, dir, base: File.dirname(@file), as: as, destination: destination)
      end

      private

      def caller_line
        caller_locations.find { |location| location.path == @file }&.lineno
      end

      def add(klass, *args, as:, destination:, **options)
        line = caller_line
        dependency = begin
          klass.new(*args, name: as&.to_s, destination: destination&.to_s, line: line, **options)
        rescue ManifestError => e
          raise ManifestError, "#{File.basename(@file)}:#{line}: #{e.message}"
        end

        [[:name, "name"], [:key, "source"], [:destination, "destination"]].each do |attribute, label|
          clash = @dependencies.find { |other| other.public_send(attribute) == dependency.public_send(attribute) }
          next unless clash

          raise ManifestError, "#{File.basename(@file)}:#{line}: #{dependency.name} has the same #{label} " \
            "as #{clash.name} (line #{clash.line}). Use as: to give one a different name."
        end
        @dependencies << dependency
        dependency
      end
    end
  end
end
