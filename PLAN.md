# dr_talon — Design Plan (DRAFT)

A Rails-style CLI for DragonRuby Game Toolkit (DRGTK): manage engine versions,
scaffold new games, and manage DragonRuby-specific (in-game, mruby-side)
dependencies.

Design decisions are marked **[D#]**; all are resolved. See
"Decisions" at the bottom.

---

## 1. Constraints from DragonRuby itself

These shape everything else:

1. **The engine must live inside each project.** DR's own docs
   (`docs/guides/starting-a-new-project.md`) say file access is sandboxed
   relative to the `dragonruby` binary, and warn against running it from a
   shared location. So we cannot do rbenv-style shims pointing at one global
   install. "Version management" = a **global cache of unpacked engines** +
   **materializing (copying) a pinned engine into the project**.
2. **Only "latest" is downloadable.**
   - Pro/Indie: `https://dragonruby.org/api/download_<pro|indie>_subscription_<os>`
     (HTTP basic auth) returns a URL to the latest zip.
   - Standard: `butler fetch dragonruby/dragonruby-gtk:<platform>` (itch.io).
   - Older versions are only available if *we* kept them → the local cache is
     the archive. `talon engine import <zip>` must be first-class.
3. **Version identity isn't in `VERSION.txt`** (that has build date + git sha).
   The release number is the first `* X.Y` heading in `CHANGELOG-CURR.txt`.
   Tier (standard/indie/pro) comes from the zip name
   (`dragonruby-pro-linux-amd64.zip`) with a `--tier` override.
4. **Some engine files must not be committed to public repos**
   (`dragonruby-publish`, `dragonruby-bind`), but DR recommends committing the
   whole engine for private/commercial games ("shelf life").
5. **`dragonruby` exits 0 even when tests fail**, so test running has to judge
   by output (the talon repo's mise task already does this).
6. Engine distribution also includes a hidden `.dragonruby/` dir (platform
   stubs, shader tools) that must be copied along with the visible files.

## 2. Naming

- Gem: `dr_talon` (the `talon` gem name is taken on RubyGems).
- Executable: `talon` **[D1, decided]**.

## 3. Command surface

Modeled on `rails` + `rbenv`/`mise` + `bundler`.

### Project scaffolding
```
talon new my_game [--engine 7.23] [--template bare|talon|<git-url>|<path>]
                  [--layout full|game-only] [--lib]
                  [--skip-git] [--skip-bundle] [--skip-deps]
talon generate scene Title          # Talon-framework generators (rails g style);
talon generate game_object Player   # only available when the project's
talon generate component Health     # dependencies.rb includes Talon
```

### Engine management
```
talon engine list                   # cached engines (* = current project's pin)
talon engine import <zip|dir> [--tier pro]
talon engine fetch [--tier pro|indie|standard]   # download latest → cache
talon engine use 7.23               # pin + materialize into current project
talon engine current                # what this project pins / has installed
talon engine which                  # path to cached engine
talon engine uninstall 7.20         # remove from cache
talon engine login                  # save dragonruby.org credentials (0600)
talon engine logout                 # delete saved credentials
talon engine outdated               # project pin vs newest cached/remote
```

### Dependencies
```
talon add github:asimmons91/talon --path lib [--ref v0.3.0] [--as talon]
talon add url:https://example.com/foo.rb --as foo.rb
talon add path:../talon --path lib  # local dev link (copy/symlink)
talon remove talon
talon install                       # engine (if missing) + deps from lockfile
talon update [name...]              # re-resolve refs, rewrite lockfile
talon outdated
```

### Workflow wrappers (replace the mise tasks in the template)
```
talon run  [ARGS...]                # ./dragonruby mygame ARGS (exec)
talon test [FILES...]               # runs *_tests.rb, parses output, real exit code;
                                    # headless (SDL dummy drivers) unless --no-headless
talon build [ARGS...]               # dragonruby-publish --only-package (never uploads)
talon serve [DIR] [--port 8080]     # dragonruby-httpd DIR PORT, default newest builds/*-html5-*/
talon clean                         # builds/ logs/ tmp/ errors/ (+ mygame/ ones)
talon doctor                        # engine present? matches pin? .dragonruby/ present?
                                    # metadata placeholders still set? deps in sync?
```

## 4. Engine management design

### Global store (XDG on Linux; platform equivalents elsewhere)
```
~/.local/share/dr_talon/engines/
  7.23-pro-linux-amd64/            # unpacked, pristine, read-only
    .talon-engine.yml              # version, tier, platform, sha256 of zip, git sha, date
    dragonruby, dragonruby-publish, .dragonruby/, docs/, samples/, ...
~/.cache/dr_talon/downloads/       # original zips (optional retention)
~/.config/dr_talon/config.yml      # default tier, default template, etc.
~/.config/dr_talon/credentials.yml # dragonruby.org login, mode 0600
```

### Project pin
`.dragonruby-version` at project root, e.g. `7.23-pro`. Platform is implied by
the host so the same pin works across team members' OSes (Pro zips are
per-host-OS but contain all export stubs).

### Materializing into a project
- Copy the cached engine into the project root, **excluding `mygame/`**
  (and optionally `samples/`, `docs/`, ctags).
- Use reflink copies (`cp --reflink=auto` semantics / `FICLONE`) when the FS
  supports it (btrfs/xfs/APFS), else plain copy. Avoid symlinks: DR resolves
  sandbox paths from the binary location.
- Write `.talon/engine.yml` (engine id + every file we placed). On
  `engine use <other>`, remove exactly those files, then lay down the new
  engine. Never touch files not in the manifest (user's `mygame/`, Gemfile...).
- **[D2, decided]** `talon new` asks whether to commit the engine. If not,
  engine paths go in `.gitignore` and `talon install` restores them from the
  cache. Either way `.dragonruby-version` is committed.

### Acquisition
1. `import`: accept zip or already-unzipped dir; detect version/tier/platform;
   copy into store.
2. `fetch` (Pro/Indie): GET the API with basic auth → follow returned URL →
   import. Credentials from `DRAGONRUBY_USERNAME`/`DRAGONRUBY_PASSWORD`, else
   prompt and offer to save to `~/.config/dr_talon/credentials.yml`
   (written with mode 0600; refuse to read it if group/world-readable).
   `talon engine logout` deletes it. **[D5, decided]**
3. `fetch` (Standard): shell out to `butler` if on PATH (offer to download it
   from `broth.itch.ovh`).

## 5. Project layouts

**[D3, decided]** Both layouts: `full` for games, `game-only` via `talon new --lib`.

- **full** (DR's recommended layout; matches `dragonruby-game-template`):
  project root = engine, game code in `mygame/`. `talon run` →
  `./dragonruby mygame`.
- **game-only** (matches the `talon` library repo): repo root *is* the game dir
  (`app/`, `lib/`, `test/`); only the runtime (`dragonruby` binary,
  `font.ttf`, and top-level DLLs on Windows) is materialized at the root and
  gitignored; `talon run` → `./dragonruby .`. Best for libraries
  (`talon new --lib`).

`Project` detection walks up from cwd looking for `.dragonruby-version`,
then infers layout from whether `mygame/app/main.rb` or `app/main.rb` exists.

## 6. Templates

- Ship built-in templates inside the gem (`lib/dr_talon/templates/`), ERB via
  Thor::Actions (`template`, `copy_file`, `inject_into_file`), just like Rails
  generators.
  - `bare`: DR's stock `mygame/` + dev tooling (Gemfile w/ rubocop,
    solargraph, solargraph-dragonruby; `.rubocop.yml`, `.solargraph.yml`,
    `.editorconfig`, `.gitignore`). The stock `mygame/` is copied from the
    cached engine (the store keeps it for this reason) rather than bundled in
    the gem, so DragonRuby's sample sprites/metadata aren't redistributed
    under the gem's MIT license.
  - `talon`: `bare` + talon dependency, `solargraph-dr_talon`, a starter
    `Talon::Game` + `Scene` in `main.rb`. Opt-in only.
  - `lib`: game-only layout with `lib/<name>.rb`, `lib/<name>/version.rb`,
    `app/main.rb` (demo), `test/test_helper.rb` and a DragonRuby test.
    File names use underscores (`my-lib` → `lib/my_lib.rb`, `MyLib`).
- Default template is `bare`; override per run with `--template` or globally
  with `default_template:` in `~/.config/dr_talon/config.yml` **[D7, decided]**.
- `--template <git-url|path>` for user templates: a repo with a
  `template.rb` (Rails app-template style, has the Thor action DSL) and/or a
  `files/` tree. *(Not in M3; later.)*
- Fill `metadata/game_metadata.txt`: DragonRuby ships the publishing fields
  commented out (`# devid=...`), so `new` uncomments and sets `gameid`,
  `gametitle`, `version`, `icon`, and `devid`/`devtitle` when known (flags or
  config); unknown ones stay commented and `talon doctor` reports them.
- When the engine isn't committed, `new` writes a marked block to
  `.gitignore` listing the engine's top-level entries plus `/.talon/`;
  `talon engine use` regenerates the block so it follows engine changes.
- Optional `mise.toml` with only `[tools] ruby = ...` (tasks become
  `talon` commands). *(Not in M3; later, probably as a config default.)*

## 7. Dependency management

**Scope:** in-game (mruby-side) code vendored into `mygame/vendor/`. Dev-time
Ruby gems (rubocop, solargraph) stay in Bundler's `Gemfile`.

### Manifest
**[D4, decided]** Keep the Foodchain DSL names so existing `dependencies.rb` files
mostly work, but evaluated by CRuby in the CLI:
```ruby
# mygame/dependencies.rb  (or Talonfile at project root)
github "asimmons91/talon", path: "lib", ref: "v0.3.0", as: "talon"
url    "https://example.com/tween.rb", as: "tween.rb"
git    "https://codeberg.org/someone/lib.git", path: "src", ref: "main"
path   "../talon", path: "lib"            # local development
```

### Locks (below `__END__`, Foodchain-style, same file)
```ruby
github "asimmons91/talon", path: "lib", ref: "v0.3.0", as: "talon"

__END__

# The lines below pin the versions of your installed dependencies.
# Managed by `talon install` / `talon update`; do not edit by hand.

github:asimmons91/talon/lib	v0.3.0	vendor/talon	c4b670c<full sha>	sha256:<vendored tree>
```
- Everything above `__END__` is user-owned and preserved verbatim (CRuby stops
  parsing at `__END__`). Everything below is regenerated by the CLI.
- `talon add`/`remove` edit the DSL section by inserting/removing lines just
  above `__END__` (single-line declarations only for `remove`).
- Columns (tab-separated, `-` when empty): key (Foodchain's format,
  `github:owner/repo/path`; the URL for `url`; `git:URL?path=sub`;
  `path:DIR`), requested ref, destination, resolved commit (or
  `sha256:` of the content for `url`), checksum of the vendored files.
  Ref and destination are recorded so editing either in the DSL re-resolves.
- **Not runtime-compatible with Foodchain**: its two-column ETag lines are
  detected, dropped and re-resolved on the next `talon install`.
- Destinations must be inside `vendor/` (talon deletes and rewrites them).
- Vendored files that differ from their lock checksum (edited locally), or
  pre-existing unmanaged files that differ from what would be installed,
  stop the install unless `--force`.
- Resolve refs → commit SHA (GitHub API / `git ls-remote`), fetch the tarball
  at that SHA, extract only the subpath. One request per dep instead of
  Foodchain's per-file contents API calls (avoids GitHub rate limits).
- `talon install` reproduces the lockfile exactly; `talon update` re-resolves.
- `doctor`/`install` warn if vendored files were edited locally (checksum).
- Vendor dir is committed (DR's publish step needs it on disk; also "shelf
  life").
- v1 is **flat** (no transitive deps). Later: a library may ship its own
  `dependencies.rb`/`dragonruby.yml` to declare deps and its vendor path.

### Require ergonomics
`talon add` prints the line to paste (`require "vendor/talon/talon.rb"`).
No generated loader and no edits to user code. **[D6, decided]**

## 8. Internal architecture

```
exe/talon
lib/dr_talon.rb
lib/dr_talon/
  cli.rb                 # Thor root: new, run, test, build, clean, doctor, install...
  cli/engine.rb          # Thor subcommand
  cli/generate.rb
  paths.rb               # XDG / macOS / Windows dirs
  config.rb
  project.rb             # root discovery, layout, pin, game dir
  engine/
    installation.rb      # value object: version, tier, platform, path
    store.rb             # list/find/add/remove cached engines
    inspector.rb         # read CHANGELOG-CURR/VERSION.txt, detect tier/platform
    importer.rb          # zip/dir → store
    materializer.rb      # copy into project + manifest; reflink when possible
    fetchers/dragonruby_api.rb
    fetchers/butler.rb
  deps/
    dsl.rb               # evaluates dependencies.rb
    lockfile.rb
    resolver.rb
    sources/{github,git,url,path}.rb
    installer.rb
  runner.rb              # spawn dragonruby; test output parsing / exit codes
  generators/
    new_game.rb
    scene.rb, game_object.rb, component.rb
  templates/{bare,talon,lib}/...
```

**Runtime deps:** `thor` (CLI + generators, what Rails uses), `rubyzip`
(portable unzip that preserves exec bits). HTTP via stdlib `net/http`.
YAML/JSON stdlib. Keep the dependency footprint small.

**Ruby support:** `>= 3.2` (as gemspec says).

**Platforms:** Linux first (dev machine). macOS needs quarantine-xattr removal
after unzip. Windows: `.exe` suffixes, no reflinks.

## 9. Testing

- Minitest (already set up) + `standard`.
- Fixture "fake engine" zips (tiny tree with `CHANGELOG-CURR.txt`,
  `VERSION.txt`, `.dragonruby/`, stub `dragonruby` shell script) so engine
  import/materialize/use are tested without real binaries.
- HTTP behind a small injectable client; fake it in tests (no network).
- Generator tests: run `talon new` into a tmpdir, assert tree/contents.
- An opt-in integration suite (`DR_TALON_ENGINE_ZIP=...`) that runs real
  `talon new && talon test` against an actual engine.

## 10. Milestones

| # | Milestone | Contents |
|---|-----------|----------|
| M0 | Skeleton | exe, Thor root, `version`, `paths`, gemspec cleanup, CI |
| M1 | Engine store | `engine import/list/which/uninstall`, inspector, store |
| M2 | Project + pin | `.dragonruby-version`, materializer + manifest, `engine use/current`, `doctor` |
| M3 | `new` | `bare` + `lib` templates, metadata filling, git init, bundle |
| M4 | Workflow | `run`, `test` (exit codes), `build`, `serve`, `clean` |
| M5 | Deps | DSL, lockfile, github/url/path sources, `add/remove/install/update/outdated` |
| M6 | Fetch | dragonruby.org API, butler, credential handling |
| M7 | Talon | `talon` template, `generate scene/game_object/component` |
| M8 | Release | README, docs, 0.1.0 to RubyGems |

## 11. Prior art to look at

- **Foodchain** (pvande): in-engine dep fetcher; already in the template.
- **drakkon** (RubyGems): DragonRuby version manager/utility CLI.
- **smaug**: older DR package manager + project tool.
- Rails generators / app templates; rbenv/mise for pin-file UX.

## Decisions

| ID | Question | Proposed default |
|----|----------|------------------|
| D1 | Executable name | **Decided:** `talon` |
| D2 | Engine in git, or pinned + restored | **Decided:** ask at `talon new` (`--commit-engine` / `--no-commit-engine` flags skip the prompt) |
| D3 | Supported layouts | **Decided:** `full` for games, `game-only` for libs (`--lib`) |
| D4 | Dependency manifest / lock format | **Decided:** Foodchain-style DSL resolved by the CLI; SHA locks kept below `__END__` in the same file |
| D5 | Credential storage for Pro/Indie fetch | **Decided:** env vars > `credentials.yml` (0600) > prompt (offers to save) |
| D6 | Require ergonomics | **Decided:** `talon add` prints the require line; no generated loader |
| D7 | Coupling to the Talon framework | **Decided:** framework-agnostic core, `bare` default; Talon is an opt-in template + generators |
| D8 | Templates bundled in gem vs pulled from `dragonruby-game-template` repo | **Decided:** bundled; `--template <git-url\|path>` for custom ones |
