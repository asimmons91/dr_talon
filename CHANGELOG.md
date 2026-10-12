## [Unreleased]

- `talon` executable with `version` (`-v`, `--version`)
- `DrTalon::Paths` for XDG / macOS / Windows data, cache and config locations (`DR_TALON_HOME` override)
- `talon engine import|list|which|uninstall`: a global cache of DragonRuby engines, imported from the downloaded zip or an extracted directory
- `talon engine use [ENGINE]`: pin an engine in `.dragonruby-version` and copy it into the project (reflinks on btrfs/XFS), tracking installed files in `.talon/engine.yml` so switching versions removes exactly those files
- `talon engine current`; `which` and `list` follow the project's pin
- `talon doctor`: checks the pin, the cached and installed engine, and `game_metadata.txt` placeholders
- `talon new PATH`: create a game (`bare` template: DragonRuby's layout, starting from the cached engine's `mygame/`) or a library (`--lib`: game-only layout with `lib/`, `app/main.rb` and a DragonRuby test). It pins and installs an engine, fills in `game_metadata.txt`, adds RuboCop/Solargraph tooling, and runs `git init` and `bundle install`
- `talon new` asks whether to commit the engine (`--[no-]commit-engine`). If not, a managed `.gitignore` block ignores it, and `talon engine use` keeps that block up to date
- `config.yml` settings: `default_template`, `dev_id`, `dev_title`
- `talon doctor` treats commented-out `game_metadata.txt` fields as unset
