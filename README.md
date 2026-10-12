# dr_talon

A Rails-style command line tool for [DragonRuby Game Toolkit](https://dragonruby.org). It manages engine versions, scaffolds new games, and manages DragonRuby dependencies.

> **Status:** early development. Engines, projects, the run/test/build commands and dependencies work; Pro/Indie downloads and Talon generators are next. See [PLAN.md](PLAN.md) for the design and roadmap.

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

### New projects

```bash
talon engine import ~/Downloads/dragonruby-pro-linux-amd64.zip   # once
talon new my_game                  # a game, in DragonRuby's layout (mygame/)
talon new my-lib --lib             # a library: lib/, app/main.rb, test/
talon help new                     # all options
```

`talon new` pins the newest cached engine (or `--engine 7.23-pro`) and installs it. It copies the engine's own sample game into `mygame/` and fills in `game_metadata.txt` (`gameid`, `gametitle`, and `devid`/`devtitle` from `--dev-id`/`--dev-title` or your config). It also adds RuboCop and Solargraph config, then runs `git init` and `bundle install` (`--skip-git`, `--skip-bundle`).

It asks whether to commit the engine to git, which DragonRuby recommends for private and commercial games. Pass `--commit-engine` or `--no-commit-engine` to skip the question. If you don't commit it, the engine's files go in a marked section of `.gitignore`, and anyone who clones the project runs `talon engine use` to restore the pinned engine. Libraries never commit the engine.

### Running, testing and building

```bash
talon run                 # ./dragonruby mygame (or . for libraries); extra args pass through
talon test                # every *_tests.rb in test/ and tests/ under the game directory
talon test test/foo_tests.rb --no-headless --timeout 30 --verbose
talon build               # dragonruby-publish --only-package: every platform into builds/
talon serve               # newest HTML5 build at http://localhost:8080/ (--port)
talon clean               # delete builds/, logs/, tmp/, errors/
```

DragonRuby's test runner always exits 0, so `talon test` reads its output instead. It prints each file's result and the details of any failure. It exits non-zero if a test fails, a file doesn't load, a file has no tests, or a run passes `--timeout` (default 120 seconds). Tests run headless by default using SDL's dummy video and audio drivers, so no window opens and they work in CI. Pass `--no-headless` for tests that need real rendering.

### Dependencies

DragonRuby doesn't load gems, so libraries are vendored into the game: their files are copied into `vendor/` inside the game directory and committed with it.

```bash
talon add github:asimmons91/talon --path lib       # vendor/talon, prints the require line
talon add github:someone/tweens --ref v1.2.0 --as tweens
talon add url:https://example.com/easing.rb
talon add path:../my_lib/lib                       # a local library, copied on every install
talon install                                      # after cloning: engine + locked dependencies
talon update [NAME...]                             # move to the newest commit of each ref
talon outdated
talon remove tweens
```

They're declared in `dependencies.rb` in the game directory (`mygame/` for games). The format is compatible with [Foodchain](https://github.com/pvande/foodchain), so existing files keep working:

```ruby
github "asimmons91/talon", path: "lib", ref: "main", as: "talon"
github :asimmons91, :talon, "lib", destination: "vendor/talon"   # Foodchain style
git "https://codeberg.org/someone/lib.git", path: "src", ref: "v2"
url "https://example.com/easing.rb"
path "../my_lib/lib"

__END__

# The lines below pin the versions of your installed dependencies.
...
```

talon owns everything below `__END__`: one tab-separated line per dependency with its key, ref, destination, locked commit (or a SHA-256 for `url`), and a checksum of the vendored files. `talon install` reproduces exactly those versions. If you edit a vendored file, talon notices and won't overwrite it unless you pass `--force`. GitHub dependencies resolve refs with `git ls-remote` and download one tarball per dependency, so they don't use up the GitHub API rate limit.

### Configuration

`~/.config/dr_talon/config.yml` (see the table below for other platforms):

```yaml
default_template: bare      # or lib
dev_id: my_itchio_username  # devid in game_metadata.txt
dev_title: My Name          # devtitle in game_metadata.txt
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
