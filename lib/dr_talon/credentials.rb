# frozen_string_literal: true

require "fileutils"
require "yaml"

module DrTalon
  Credentials = Data.define(:username, :password, :source)

  # A dragonruby.org login for downloading Pro/Indie engines. Looked up in
  # +DRAGONRUBY_USERNAME+/+DRAGONRUBY_PASSWORD+, then {Paths#credentials_file}
  # (which must be readable only by its owner).
  #
  # @!attribute [r] source
  #   @return [Symbol] +:env+, +:file+ or +:prompt+
  class Credentials
    ENV_USERNAME = "DRAGONRUBY_USERNAME"
    ENV_PASSWORD = "DRAGONRUBY_PASSWORD"

    # The credentials file can be read by other users.
    class InsecureFile < Error; end

    # @param env [Hash]
    # @param path [String]
    # @return [Credentials, nil]
    # @raise [InsecureFile, Error]
    def self.lookup(env: ENV, path: Paths.new.credentials_file)
      from_env(env) || load(path)
    end

    # @return [Credentials, nil] only when both variables are set
    def self.from_env(env = ENV)
      username, password = env.values_at(ENV_USERNAME, ENV_PASSWORD)
      return nil if username.to_s.empty? || password.to_s.empty?

      new(username: username, password: password, source: :env)
    end

    # @param path [String]
    # @return [Credentials, nil]
    # @raise [InsecureFile] if group or others can read the file
    # @raise [Error] if it isn't a mapping with username and password
    def self.load(path)
      return nil unless File.file?(path)

      mode = File.stat(path).mode & 0o777
      if !Gem.win_platform? && mode.anybits?(0o077)
        raise InsecureFile, "#{path} is readable by other users (mode #{format("%o", mode)}). " \
          "Run `chmod 600 #{path}` or `talon engine login` again."
      end

      data = YAML.safe_load_file(path)
      unless data.is_a?(Hash) && !data["username"].to_s.empty? && !data["password"].to_s.empty?
        raise Error, "#{path} should contain username: and password:."
      end

      new(username: data["username"].to_s, password: data["password"].to_s, source: :file)
    rescue Psych::SyntaxError => e
      raise Error, "Can't read #{path}: #{e.message}"
    end

    # @param path [String]
    # @return [Boolean] whether a file was deleted
    def self.delete(path)
      return false unless File.exist?(path)

      File.unlink(path)
      true
    end

    # Writes the file readable only by its owner (mode 0600).
    #
    # @param path [String]
    # @return [void]
    def save(path)
      FileUtils.mkdir_p(File.dirname(path))
      File.unlink(path) if File.exist?(path)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(YAML.dump({"username" => username, "password" => password}))
      end
      File.chmod(0o600, path)
    end

    # @return [HTTP::Auth]
    def to_auth
      HTTP::Auth.new(username: username, password: password)
    end

    # Never print the password.
    def inspect
      "#<#{self.class.name} username=#{username.inspect} source=#{source.inspect}>"
    end
    alias_method :to_s, :inspect
  end
end
