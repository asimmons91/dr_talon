# frozen_string_literal: true

module DrTalon
  # Health checks for a project, reported by +talon doctor+.
  class Doctor
    # @!attribute [r] status
    #   @return [Symbol] +:ok+, +:warning+ or +:error+
    # @!attribute [r] message
    #   @return [String]
    Check = Data.define(:status, :message)

    # Values DragonRuby ships in +game_metadata.txt+ that must be changed
    # before publishing.
    METADATA_PLACEHOLDERS = {
      "devid" => "your_itchio_username",
      "devtitle" => "Your Itch.io Display Name",
      "gameid" => "your_itchio_game_id",
      "gametitle" => "Your Game Title"
    }.freeze

    # Publishing fields in +game_metadata.txt+ that are missing, commented out
    # (as DragonRuby ships them) or still DragonRuby's placeholder.
    #
    # @param project [Project]
    # @return [Array<String>, nil] nil when there's no metadata file
    def self.unset_metadata(project)
      path = File.join(project.game_dir, "metadata", "game_metadata.txt")
      return nil unless File.file?(path)

      values = File.readlines(path, chomp: true).filter_map do |line|
        line.strip.split("=", 2) if !line.lstrip.start_with?("#") && line.include?("=")
      end.to_h

      METADATA_PLACEHOLDERS.select { |key, placeholder| values[key].nil? || values[key] == placeholder }.keys
    end

    # @param project [Project]
    # @param store [Engine::Store]
    # @param host_platform [String]
    def initialize(project, store, host_platform: Engine.host_platform)
      @project = project
      @store = store
      @host_platform = host_platform
      @materializer = Engine::Materializer.new(project)
    end

    # @return [Array<Check>]
    def checks
      @checks = []
      check_game
      check_engine
      check_dependencies
      check_metadata
      @checks
    end

    private

    def ok(message) = @checks << Check.new(status: :ok, message: message)

    def warning(message) = @checks << Check.new(status: :warning, message: message)

    def error(message) = @checks << Check.new(status: :error, message: message)

    def check_game
      layout = @project.layout
      if layout
        ok "Game found in #{(layout == :full) ? "mygame/" : "the project root"} (#{layout.to_s.tr("_", "-")} layout)"
      else
        error "No mygame/app/main.rb or app/main.rb found"
      end
    end

    def check_engine
      pin = begin
        @project.pin
      rescue Error => e
        return error(e.message)
      end
      return error("No #{Project::PIN_FILE}. Pin an engine with `talon engine use VERSION`.") unless pin

      expected = expected_engine(pin)
      return unless expected

      manifest = begin
        @materializer.manifest
      rescue Error => e
        return error(e.message)
      end

      if manifest.nil?
        error "#{expected.id} isn't installed in the project. Run `talon engine use`."
      elsif manifest.engine != expected.id
        error "The project has #{manifest.engine} installed but #{Project::PIN_FILE} pins #{pin}. Run `talon engine use`."
      else
        check_installed_files(manifest)
      end
    end

    def expected_engine(pin)
      spec = Engine::Spec.new(version: pin.version, tier: pin.tier, platform: @host_platform)
      installation = @store.find(spec)
      ok "#{Project::PIN_FILE} pins #{pin}; #{installation.id} is cached"
      installation
    rescue Engine::NotFound
      error "#{Project::PIN_FILE} pins #{pin}, but no matching #{@host_platform} engine is cached. " \
        "Import it with `talon engine import <zip>`."
      nil
    rescue Engine::Ambiguous => e
      error e.message
      nil
    end

    def check_installed_files(manifest)
      missing = manifest.files.reject { |relative| File.exist?(@project.path(relative)) }
      if missing.any?
        count = (missing.size == 1) ? "1 engine file is" : "#{missing.size} engine files are"
        return error("#{count} missing (e.g. #{missing.first}). Run `talon engine use`.")
      end

      binary = %w[dragonruby dragonruby.exe].map { |name| @project.path(name) }.find { |path| File.file?(path) }
      if binary.nil?
        error "No dragonruby binary in the project root"
      elsif !File.executable?(binary)
        error "#{File.basename(binary)} isn't executable"
      else
        ok "#{manifest.engine} is installed (#{manifest.files.size} files)"
      end
    end

    def check_dependencies
      manifest = Deps::Manifest.for(@project)
      return unless manifest.exist?

      count = manifest.dependencies.size
      problems = Deps::Installer.new(@project).problems
      problems.each do |entry|
        dependency = entry[:dependency]
        case entry[:problem]
        when :unlocked then error "#{dependency.name} isn't installed or locked yet. Run `talon install`."
        when :missing then error "#{dependency.name} is locked but #{dependency.destination} is missing. Run `talon install`."
        when :modified then warning "#{dependency.destination} has local changes; `talon install --force` restores it"
        end
      end
      ok "#{count} dependenc#{(count == 1) ? "y" : "ies"} installed" if problems.empty?
    rescue Error => e
      error e.message
    end

    def check_metadata
      unset = self.class.unset_metadata(@project)
      if unset.nil?
        warning("No metadata/game_metadata.txt; it's needed to publish") if @project.layout == :full
      elsif unset.empty?
        ok "game_metadata.txt is filled in"
      else
        warning "game_metadata.txt doesn't set #{unset.join(", ")} yet (needed to publish)"
      end
    end
  end
end
