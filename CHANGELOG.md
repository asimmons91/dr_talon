## [Unreleased]

- `talon` executable with `version` (`-v`, `--version`)
- `DrTalon::Paths` for XDG / macOS / Windows data, cache and config locations (`DR_TALON_HOME` override)
- `talon engine import|list|which|uninstall`: a global cache of DragonRuby engines, imported from the downloaded zip or an extracted directory
- `talon engine use [ENGINE]`: pin an engine in `.dragonruby-version` and copy it into the project (reflinks on btrfs/XFS), tracking installed files in `.talon/engine.yml` so switching versions removes exactly those files
- `talon engine current`; `which` and `list` follow the project's pin
- `talon doctor`: checks the pin, the cached and installed engine, and `game_metadata.txt` placeholders
