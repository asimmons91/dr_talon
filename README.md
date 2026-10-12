# dr_talon

`talon` is a Rails-style command line tool for [DragonRuby Game Toolkit](https://dragonruby.org):

- **Engines.** It keeps a cache of DragonRuby versions, downloads new ones, and pins one per project, so every
  clone runs the same engine.
- **Projects.** `talon new` scaffolds games and libraries; `talon run`, `test`, `build` and `serve` replace the
  usual shell scripts. `talon test` reports failures properly, even though DragonRuby itself always exits 0.
- **Dependencies.** It vendors DragonRuby libraries from GitHub, git, URLs or local paths, locked to exact commits.
- **Talon.** Optionally, it scaffolds games on the [Talon](https://github.com/asimmons91/talon) framework and
  generates scenes, components and prefabs.

## Requirements

- Ruby 3.2 or newer
- git, for GitHub and git dependencies
- A DragonRuby engine. Any license works, including the free [Jam license](#downloading-engines), which `talon`
  can download for you.

`talon` is developed and tested on Linux. It handles macOS and Windows paths and engine names, but has seen less
use there.

## Installation

```bash
gem install dr_talon
```

The gem installs a `talon` executable. `talon help` lists every command, and `talon help COMMAND` describes one.

## Quick start

```bash
talon engine fetch --tier jam      # or: talon engine import ~/Downloads/dragonruby-pro-linux-amd64.zip
talon new my_game                  # asks whether to commit the engine, and your itch.io name
cd my_game
talon run                          # ./dragonruby mygame
talon test                         # *_tests.rb in mygame/test/ and mygame/tests/ (one starter test)
talon build                        # package every platform your license allows into builds/
talon doctor                       # check the engine, dependencies and game metadata
```

`dragonruby-publish` won't package a game until `game_metadata.txt` names its developer, so `talon new` asks for
your itch.io username and display name, unless you pass `--dev-id` and `--dev-title` or set them in your
[config](#configuration). It only asks in a terminal; scripts aren't prompted.

## Engines

DragonRuby only offers its latest release for download, so `talon` keeps a cache of every engine you fetch or
import. That cache is how you get back to an older version.

```bash
talon engine import ~/Downloads/dragonruby-pro-linux-amd64.zip   # the zip as downloaded, or an extracted directory
talon engine list
talon engine which 7.23            # 7.23, 7.23-pro or 7.23-pro-linux-amd64
talon engine uninstall 7.23        # asks first; --yes to skip
```

Engines are identified as `VERSION-TIER-PLATFORM`, for example `7.23-pro-linux-amd64`. The version comes from
`CHANGELOG-CURR.txt` and the platform from the engine directory name. The tier comes from the zip or directory
name; pass `--tier pro|indie|standard|jam` if the name doesn't include it.

### Downloading engines

```bash
talon engine fetch --tier jam        # the free Jam license; no account needed
talon engine login                   # once: saves your dragonruby.org login (mode 600)
talon engine fetch                   # latest release, same tier as your newest cached engine
talon engine fetch --tier indie
talon engine fetch --tier standard   # via itch.io's butler, after `butler login`
talon engine logout
```

- **Jam.** The [Jam license](https://dragonruby.itch.io/dragonruby-gtk/devlog/1620970/dragonruby-jam-license-free-to-all)
  is free and can be used commercially. It has Standard's full API but only exports to the web. `talon` downloads
  it the same way the Download button on [DragonRuby's itch.io page](https://dragonruby.itch.io/dragonruby-gtk#demo)
  does, for Linux (x64 and arm64), macOS and Windows. If itch.io changes that page, download the zip by hand and
  run `talon engine import`.
- **Pro and Indie.** These come from dragonruby.org's subscription API with your account's login. `talon` looks
  for it in `DRAGONRUBY_USERNAME` and `DRAGONRUBY_PASSWORD`, then in the file saved by `talon engine login`, and
  otherwise asks for it (offering to save it). The saved file holds the password in plain text, so it must be
  readable only by you; `talon` refuses to use it otherwise.
- **Standard.** This comes from itch.io through [butler](https://itch.io/docs/butler/).

### Pinning an engine to a project

```bash
cd my_game
talon engine use 7.23-pro    # pin in .dragonruby-version and install the engine here
talon engine use             # after cloning: install whatever is pinned
talon engine current         # pinned vs installed
```

DragonRuby expects its engine files next to the game, so `talon engine use` copies the cached engine into the
project. On btrfs and XFS the files are cloned (reflinked), so each copy takes almost no extra disk space.

- **The pin.** `.dragonruby-version` holds only the version and tier (`7.23-pro`), so it works on every OS.
- **What gets copied.** Games in DragonRuby's layout (`mygame/app/main.rb`) get every engine file except
  `mygame/`. Libraries, whose root is the game directory (`app/main.rb`), get just the `dragonruby` binary and
  `font.ttf`.
- **Switching versions.** The installed files are listed in `.talon/engine.yml`. Switching engines removes exactly
  those files and never touches `mygame/` or your other files. If an existing file would be overwritten and
  differs from the engine's copy, the install stops until you pass `--force`.

## Projects

```bash
talon new my_game                    # a game, in DragonRuby's layout (mygame/)
talon new my-lib --lib               # a library: lib/, app/main.rb, test/
talon new my_game --template talon   # a game on the Talon framework (see below)
talon help new                       # all options
```

`talon new` pins the newest cached engine (or `--engine 7.23-pro`) and installs it. It also:

- copies the engine's own sample game into `mygame/`
- adds a starter test, `mygame/tests/main_tests.rb`
- fills in `game_metadata.txt`: `gameid` and `gametitle` from the name, and `devid`/`devtitle` from
  `--dev-id`/`--dev-title`, your config, or by asking
- adds RuboCop and Solargraph config
- runs `git init` and `bundle install` (`--skip-git`, `--skip-bundle`)

It asks whether to commit the engine to git, which DragonRuby recommends for private and commercial games. Pass
`--commit-engine` or `--no-commit-engine` to skip the question. If you don't commit it, the engine's files go in a
marked section of `.gitignore`, and anyone who clones the project runs `talon install` to restore it. Libraries
never commit the engine.

`talon doctor` checks that the pinned engine is cached and installed, that dependencies are installed and
unmodified, and that `game_metadata.txt` is ready to publish.

### Running, testing and building

```bash
talon run                 # ./dragonruby mygame (or . for libraries); extra args such as --record pass through
talon test                # every *_tests.rb in test/ and tests/ under the game directory
talon test tests/player_tests.rb --no-headless --timeout 30 --verbose
talon build               # dragonruby-publish --only-package: into builds/, never uploaded
talon serve               # the newest HTML5 build at http://localhost:8080/ (--port)
talon clean               # delete builds/, logs/, tmp/ and errors/
```

DragonRuby's test runner always exits 0, so `talon test` reads its output instead. It prints each file's result
and the details of any failure, and it exits non-zero if a test fails, a file doesn't load, a file has no tests,
or a run passes `--timeout` (default 120 seconds).

Tests run headless by default, using SDL's dummy video and audio drivers, so no window opens and they work in CI.
Pass `--no-headless` for tests that need real rendering.

## Dependencies

DragonRuby doesn't load gems, so libraries are vendored into the game: their files are copied into `vendor/` inside
the game directory and committed with it.

```bash
talon add github:asimmons91/talon --path lib       # vendor/talon, then prints the require line
talon add github:someone/tweens --ref v1.2.0 --as tweens
talon add url:https://example.com/easing.rb
talon add path:../my_lib/lib                       # a local library, copied on every install
talon install                                      # after cloning: the engine, then locked dependencies
talon update [NAME...]                             # move to the newest commit of each ref
talon outdated
talon remove tweens
```

Dependencies are declared in `dependencies.rb` in the game directory (`mygame/` for games). The format is
compatible with [Foodchain](https://github.com/pvande/foodchain), so existing files keep working:

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

`talon` owns everything below `__END__`. Each dependency gets one tab-separated line with its key, ref,
destination, locked commit (or a SHA-256 for `url`), and a checksum of the vendored files.

- `talon install` reproduces exactly those versions.
- If you edit a vendored file, `talon` notices and won't overwrite it unless you pass `--force`.
- GitHub dependencies resolve refs with `git ls-remote` and download one tarball each, so they don't use up the
  GitHub API rate limit. Private repositories need `git:` with an SSH URL instead.

## Talon games

[Talon](https://github.com/asimmons91/talon) is a scene, game object and component framework for DragonRuby.
`talon` works with any DragonRuby game; Talon support is opt-in.

```bash
talon new my_game --template talon     # Talon vendored, a Title scene, a Spin component and a test
talon generate scene MainMenu          # app/scenes/main_menu.rb + tests/scenes/main_menu_tests.rb
talon generate component Health        # app/components/health.rb + test
talon g prefab EnemyShip               # app/prefabs/enemy_ship.rb + test (spawn(:ship, EnemyShip))
```

DragonRuby only loads files that are explicitly required, so generators add each new file's `require` to a
marked section of `app/main.rb`, ordered components, then prefabs, then scenes. If that section is missing, they
print the line for you to paste.

Generators only run in projects whose `dependencies.rb` includes Talon. To use them in an existing game, run
`talon add github:asimmons91/talon --path lib` first.

## Configuration

`~/.config/dr_talon/config.yml` (see below for other platforms):

```yaml
default_template: bare      # or talon, or lib
dev_id: my_itchio_username  # devid in game_metadata.txt
dev_title: My Name          # devtitle in game_metadata.txt
```

### Where talon keeps its files

| | Linux | macOS | Windows |
|---|---|---|---|
| Engines (data) | `$XDG_DATA_HOME/dr_talon` (`~/.local/share/dr_talon`) | `~/Library/Application Support/dr_talon` | `%LOCALAPPDATA%\dr_talon` |
| Downloads (cache) | `$XDG_CACHE_HOME/dr_talon` (`~/.cache/dr_talon`) | `~/Library/Caches/dr_talon` | `%LOCALAPPDATA%\dr_talon\cache` |
| Config and login | `$XDG_CONFIG_HOME/dr_talon` (`~/.config/dr_talon`) | `~/Library/Application Support/dr_talon` | `%APPDATA%\dr_talon` |

On macOS, explicitly set `XDG_*` variables take precedence. Setting `DR_TALON_HOME` puts everything under that one
directory (`data/`, `cache/`, `config/`).

## Development

```bash
bin/setup                # install dependencies
bundle exec rake         # tests + standardrb
bundle exec exe/talon    # try the CLI from the checkout
```

The tests never need a real DragonRuby engine or the network. They build small fake engines, use local git
repositories in place of GitHub, and run HTTP against a local server. Real DragonRuby output is kept as fixtures in
`test/fixtures/dragonruby/`. The design and its decisions are in [PLAN.md](PLAN.md).

### Releasing

Add changes to the `## [Unreleased]` section of `CHANGELOG.md` as you go. To release:

```bash
bundle exec rake release:prepare[minor]   # or major, patch, or an explicit version like 1.2.3
git push origin main v0.2.0               # the command it prints
```

`release:prepare` runs the tests, bumps `version.rb` and `Gemfile.lock`, moves the Unreleased notes under a dated
heading, and commits and tags the release. The first release is `rake release:prepare[0.1.0]`: the current
version, since it was never tagged.

Pushing the tag runs `.github/workflows/release.yml`. It checks that the tag, version and changelog agree, runs
the tests, publishes the gem to RubyGems.org with [Trusted Publishing](https://guides.rubygems.org/trusted-publishing/),
and creates the GitHub release from that version's changelog notes.

One-time setup: on RubyGems.org, add a trusted publisher for this repository with the workflow `release.yml` and the
environment `release`. Use a "pending" trusted publisher, since the gem has never been pushed.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/asimmons91/dr_talon. This project is
intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the
[code of conduct](https://github.com/asimmons91/dr_talon/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
DragonRuby Game Toolkit itself is commercial software under its own license; `talon` doesn't include any part of it.
