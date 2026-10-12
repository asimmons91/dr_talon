# dr_talon

A Rails-style command line tool for [DragonRuby Game Toolkit](https://dragonruby.org). It manages engine versions, scaffolds new games, and manages DragonRuby dependencies.

> **Status:** early development. Engine caching and per-project pinning work; scaffolding and dependencies are next. See [PLAN.md](PLAN.md) for the design and roadmap.

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

### Engines

DragonRuby only offers its latest release for download, so talon keeps a cache of every engine you import. That cache is how you get back to older versions.

```bash
talon engine import ~/Downloads/dragonruby-pro-linux-amd64.zip   # or an extracted directory
talon engine list
talon engine which 7.23          # 7.23, 7.23-pro or 7.23-pro-linux-amd64
talon engine uninstall 7.23      # asks first; --yes to skip
```

### Projects

```bash
cd my_game
talon engine use 7.23-pro    # pin in .dragonruby-version and install the engine here
talon engine use             # after cloning: install whatever is pinned
talon engine current         # pinned vs installed
talon doctor                 # check the pin, installed engine and game metadata
```

`talon engine use` works in a directory with `.dragonruby-version`, `mygame/app/main.rb` (DragonRuby's full layout) or `app/main.rb` (game-only layout, for libraries). Full-layout projects get every engine file except `mygame/`. Game-only projects get just the `dragonruby` binary and `font.ttf`.

The pin holds only the version and tier, so it works on every developer's OS. The files talon installs are listed in `.talon/engine.yml`. Switching engines removes exactly those files and never touches `mygame/` or your other files. If an existing file would be overwritten and differs from the engine's copy, the install stops; pass `--force` to overwrite it. On btrfs and XFS, engine files are cloned (reflinked) from the cache, so each project's copy takes almost no extra disk space.

Engines are identified as `VERSION-TIER-PLATFORM`, for example `7.23-pro-linux-amd64`. The version comes from `CHANGELOG-CURR.txt` and the platform from the engine directory name. The tier comes from the zip or directory name; pass `--tier standard|indie|pro` if the name doesn't include it.

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
