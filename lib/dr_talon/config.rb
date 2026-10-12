# frozen_string_literal: true

require "yaml"

module DrTalon
  Config = Data.define(:default_template, :dev_id, :dev_title)

  # User settings from +config.yml+ (see {Paths#config_file}):
  #
  #   default_template: bare      # template for `talon new`
  #   dev_id: my_itchio_username  # devid in game_metadata.txt
  #   dev_title: My Name          # devtitle in game_metadata.txt
  class Config
    DEFAULTS = {default_template: "bare", dev_id: nil, dev_title: nil}.freeze

    # @param path [String]
    # @return [Config] defaults for anything the file doesn't set
    # @raise [Error] if the file isn't a YAML mapping
    def self.load(path = Paths.new.config_file)
      data = File.file?(path) ? YAML.safe_load_file(path) : {}
      data ||= {}
      raise Error, "#{path} should contain a YAML mapping." unless data.is_a?(Hash)

      new(**DEFAULTS.to_h { |key, default| [key, data.fetch(key.to_s, default)&.to_s] })
    rescue Psych::SyntaxError => e
      raise Error, "Can't read #{path}: #{e.message}"
    end
  end
end
