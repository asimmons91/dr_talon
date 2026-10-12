# dr_talon

A Rails-style command line tool for [DragonRuby Game Toolkit](https://dragonruby.org). It manages engine versions, scaffolds new games, and manages DragonRuby dependencies.

> **Status:** early development. Only `talon version` exists so far. See [PLAN.md](PLAN.md) for the design and roadmap.

## Installation

```bash
gem install dr_talon
```

The gem installs a `talon` executable.

## Usage

```bash
talon version      # or talon -v / talon --version
talon help
```

### Where talon keeps its files

| | Linux | macOS | Windows |
|---|---|---|---|
| Engines (data) | `$XDG_DATA_HOME/dr_talon` (`~/.local/share/dr_talon`) | `~/Library/Application Support/dr_talon` | `%LOCALAPPDATA%\dr_talon` |
| Downloads (cache) | `$XDG_CACHE_HOME/dr_talon` (`~/.cache/dr_talon`) | `~/Library/Caches/dr_talon` | `%LOCALAPPDATA%\dr_talon\cache` |
| Config | `$XDG_CONFIG_HOME/dr_talon` (`~/.config/dr_talon`) | `~/Library/Application Support/dr_talon` | `%APPDATA%\dr_talon` |

On macOS, explicitly set `XDG_*` variables take precedence. Setting `DR_TALON_HOME` puts everything under that one directory (`data/`, `cache/`, `config/`).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then run `bundle exec rake` to run the tests and the [standard](https://github.com/standardrb/standard) linter. Run `bundle exec exe/talon` to try the CLI, or `bin/console` for an interactive prompt.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/asimmons91/dr_talon. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/asimmons91/dr_talon/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
