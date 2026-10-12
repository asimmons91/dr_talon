## [Unreleased]

## [0.1.0] - 2026-10-11

First release: `talon`, a Rails-style CLI for DragonRuby Game Toolkit.

### Engines

- `talon engine import <zip|dir>` caches a DragonRuby engine as `VERSION-TIER-PLATFORM`, reading the version from
  `CHANGELOG-CURR.txt`, the platform from the engine directory, and the tier from the zip name (or `--tier`).
  Executable bits and the hidden `.dragonruby/` directory are kept; re-importing the same zip is a no-op.
- `talon engine fetch` downloads the latest engine for this machine: Pro and Indie from dragonruby.org with your
  account login, the free Jam license from DragonRuby's itch.io page with no account, and Standard with itch.io's
  butler. The tier defaults to your newest cached engine's.
- `talon engine login` / `logout` check and save, or delete, a dragonruby.org login in `credentials.yml` (mode 0600;
  refused if others can read it). `DRAGONRUBY_USERNAME` / `DRAGONRUBY_PASSWORD` take precedence.
- `talon engine list`, `which`, `uninstall` (asks first, since the cache may be the only copy of an old version).
- `talon engine use [ENGINE]` pins an engine in `.dragonruby-version` (version and tier only, so it works on every
  OS) and copies it into the project, cloning files on btrfs/XFS. Installed files are tracked in
  `.talon/engine.yml`, so switching engines removes exactly those; `mygame/` and your own files are never touched,
  and differing files stop the install unless `--force`. `talon engine current` shows pinned vs installed.

### Projects

- `talon new NAME` creates a game in DragonRuby's layout from the cached engine's own `mygame/`, with a starter
  test, RuboCop and Solargraph config, `game_metadata.txt` filled in (`--title`, `--dev-id`, `--dev-title`,
  `config.yml`, or asked for in a terminal, since `dragonruby-publish` needs them), and `git init` /
  `bundle install`. It asks whether to commit the engine; if not, a managed `.gitignore` block
  ignores it and `talon engine use` keeps the block current.
- `talon new NAME --lib` creates a library (the repository root is the game directory) with `lib/`, a demo
  `app/main.rb` and a DragonRuby test.
- `talon new NAME --template talon` creates a game on the [Talon](https://github.com/asimmons91/talon) framework,
  with Talon vendored, a `Title` scene, a `Spin` component and a test.
- `talon generate scene|component|prefab NAME` (alias `talon g`) writes Talon code and a DragonRuby test, and adds
  the require to `app/main.rb`.
- `talon doctor` checks the pin, the cached and installed engine, dependencies, and `game_metadata.txt`.
- `config.yml` settings: `default_template`, `dev_id`, `dev_title`.

### Running, testing and building

- `talon run [ARGS...]` runs the game; arguments such as `--record` pass through to `dragonruby`.
- `talon test [FILES...]` runs each `*_tests.rb` with `dragonruby --test`, headless by default, and reads
  DragonRuby's output (it always exits 0) to report failures, files that don't load, files with no tests and
  timeouts, exiting non-zero on any of them.
- `talon build` packages every platform with `dragonruby-publish --only-package`; `talon serve` serves the newest
  HTML5 build with `dragonruby-httpd`; `talon clean` deletes `builds/`, `logs/`, `tmp/` and `errors/`.

### Dependencies

- Declared in the game directory's `dependencies.rb` with a Foodchain-compatible DSL (`github`, `git`, `url`,
  `path`), vendored into `vendor/`, and locked below `__END__` to commit SHAs (or SHA-256s for URLs) with a checksum
  of the vendored files. Foodchain's ETag locks are replaced on the first install.
- `talon add SOURCE` (`github:owner/repo`, `git:URL`, `url:URL`, `path:DIR`; `--path`, `--ref`, `--as`) installs a
  dependency and prints the line to require it; `talon remove`, `talon update`, `talon outdated`.
- `talon install` restores the pinned engine if it's missing, then the locked dependencies. Locally edited vendored
  files stop it unless `--force`.
- GitHub dependencies resolve refs with `git ls-remote` and download one tarball per dependency.

[Unreleased]: https://github.com/asimmons91/dr_talon/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/asimmons91/dr_talon/releases/tag/v0.1.0
