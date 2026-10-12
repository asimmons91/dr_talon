# frozen_string_literal: true

require "test_helper"

class TestDepsInstaller < Minitest::Test
  include EngineFixtures
  include DepsFixtures

  Deps = DrTalon::Deps

  def setup
    @dir = File.realpath(Dir.mktmpdir)
    @remotes = File.join(@dir, "remotes")
    @v1 = commit_to(@remotes, "asimmons91", "talon", {"lib/talon.rb" => "v1", "README.md" => "readme"}, tag: "v1")
    @root = build_project(@dir)
    @project = DrTalon::Project.new(@root)
    @context = deps_context(@remotes)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # Rewrites the declarations, keeping the lock section as a user edit would.
  def declare(content)
    path = File.join(@root, "mygame", "dependencies.rb")
    locks = File.file?(path) ? File.read(path).partition(/^__END__\n/).drop(1).join : ""
    File.write(path, content + locks)
  end

  def install(**options)
    Deps::Installer.new(@project, context: @context, **options.slice(:force)).install(**options.except(:force))
  end

  def vendored(*relative)
    File.join(@root, "mygame", "vendor", *relative)
  end

  def locks
    Deps::Manifest.for(@project).locks
  end

  def test_installs_a_github_subpath_and_locks_it
    declare(%(github "asimmons91/talon", path: "lib"\n))

    changes = install

    assert_equal [[:installed, "talon", @v1]], changes.map { |c| [c.action, c.name, c.commit] }
    assert_equal "v1", File.read(vendored("talon", "talon.rb"))
    refute File.exist?(vendored("talon", "README.md"))
    lock = locks.first
    assert_equal ["github:asimmons91/talon/lib", nil, "vendor/talon", @v1], lock.to_a.first(4)
    assert_equal Deps::Tree.checksum(vendored("talon")), lock.checksum
  end

  def test_locked_versions_are_reused_without_network
    declare(%(github "asimmons91/talon", path: "lib"\n))
    install
    commit_to(@remotes, "asimmons91", "talon", {"lib/talon.rb" => "v2"})
    FileUtils.rm_rf(vendored("talon"))
    requests = @context.http.requests.size

    changes = install

    assert_equal [:installed], changes.map(&:action)
    assert_equal "v1", File.read(vendored("talon", "talon.rb")), "the locked commit, not the newest"
    assert_equal requests + 1, @context.http.requests.size

    assert_equal [:unchanged], install.map(&:action)
    assert_equal requests + 1, @context.http.requests.size, "nothing fetched when up to date"
  end

  def test_update_moves_to_the_newest_commit
    declare(%(github "asimmons91/talon", path: "lib"\n))
    install
    v2 = commit_to(@remotes, "asimmons91", "talon", {"lib/talon.rb" => "v2"})

    changes = install(update: ["talon"])

    assert_equal [[:updated, @v1, v2]], changes.map { |c| [c.action, c.previous, c.commit] }
    assert_equal "v2", File.read(vendored("talon", "talon.rb"))
    assert_equal v2, locks.first.commit
  end

  def test_changing_the_ref_re_resolves
    declare(%(github "asimmons91/talon", path: "lib"\n))
    commit_to(@remotes, "asimmons91", "talon", {"lib/talon.rb" => "v2"})
    install
    assert_equal "v2", File.read(vendored("talon", "talon.rb"))

    declare(%(github "asimmons91/talon", path: "lib", ref: "v1"\n))
    install

    assert_equal "v1", File.read(vendored("talon", "talon.rb"))
    assert_equal "v1", locks.first.ref
  end

  def test_local_edits_stop_the_install_unless_forced
    declare(%(github "asimmons91/talon", path: "lib"\n))
    install
    File.write(vendored("talon", "talon.rb"), "hacked")
    commit_to(@remotes, "asimmons91", "talon", {"lib/talon.rb" => "v2"})

    assert_raises(Deps::ModifiedError) { install(update: true) }
    assert_equal "hacked", File.read(vendored("talon", "talon.rb"))

    install(update: true, force: true)
    assert_equal "v2", File.read(vendored("talon", "talon.rb"))
  end

  def test_force_restores_local_edits_at_the_locked_commit
    declare(%(github "asimmons91/talon", path: "lib"\n))
    install
    File.write(vendored("talon", "talon.rb"), "hacked")

    assert_equal [:restored], install(force: true).map(&:action)
    assert_equal "v1", File.read(vendored("talon", "talon.rb"))
  end

  def test_unmanaged_files_are_adopted_only_when_identical
    declare(%(github "asimmons91/talon", path: "lib"\n))
    FileUtils.mkdir_p(vendored("talon"))
    File.write(vendored("talon", "talon.rb"), "v1")

    assert_equal [:installed], install.map(&:action)

    File.write(Deps::Manifest.for(@project).path, %(github "asimmons91/talon", path: "lib"\n))
    File.write(vendored("talon", "talon.rb"), "someone else's")
    assert_raises(Deps::ModifiedError) { install }
  end

  def test_removed_dependencies_are_deleted
    declare(%(github "asimmons91/talon", path: "lib"\nurl "https://x.test/easing.rb"\n))
    @context.http.files["https://x.test/easing.rb"] = "easing"
    install

    declare(%(url "https://x.test/easing.rb"\n))
    changes = install

    assert_equal [[:unchanged, "easing.rb"], [:removed, "talon"]], changes.map { |c| [c.action, c.name] }
    refute File.exist?(vendored("talon"))
    assert_equal ["https://x.test/easing.rb"], locks.map(&:key)
  end

  def test_modified_removed_dependencies_are_kept
    declare(%(github "asimmons91/talon", path: "lib"\n))
    install
    File.write(vendored("talon", "talon.rb"), "hacked")
    declare("")

    assert_equal [:kept], install.map(&:action)
    assert File.exist?(vendored("talon", "talon.rb"))
    assert_empty locks
  end

  def test_last_removal_tidies_vendor
    declare(%(github "asimmons91/talon", path: "lib"\n))
    install
    declare("")

    install

    refute File.exist?(File.join(@root, "mygame", "vendor"))
  end

  def test_moving_a_destination
    declare(%(github "asimmons91/talon", path: "lib"\n))
    install

    declare(%(github "asimmons91/talon", path: "lib", as: "framework"\n))
    install

    refute File.exist?(vendored("talon"))
    assert_equal "v1", File.read(vendored("framework", "talon.rb"))
  end

  def test_url_dependencies_are_pinned_by_digest
    declare(%(url "https://x.test/easing.rb"\n))
    @context.http.files["https://x.test/easing.rb"] = "one"
    install
    FileUtils.rm_f(vendored("easing.rb"))
    @context.http.files["https://x.test/easing.rb"] = "two"

    error = assert_raises(Deps::FetchError) { install }
    assert_match(/talon update easing\.rb/, error.message)

    install(update: true)
    assert_equal "two", File.read(vendored("easing.rb"))
  end

  def test_path_dependencies_are_copied_every_time
    library = File.join(@dir, "my_lib")
    FileUtils.mkdir_p(library)
    File.write(File.join(library, "my_lib.rb"), "one")
    declare(%(path "#{library}"\n))

    assert_equal [:installed], install.map(&:action)
    assert_equal [:unchanged], install.map(&:action)
    File.write(File.join(library, "my_lib.rb"), "two")

    assert_equal [:updated], install.map(&:action)
    assert_equal "two", File.read(vendored("my_lib", "my_lib.rb"))
  end

  def test_git_dependencies
    declare(%(git "file://#{@remotes}/asimmons91/talon.git", path: "lib/talon.rb", ref: "v1"\n))
    commit_to(@remotes, "asimmons91", "talon", {"lib/talon.rb" => "v2"})

    install

    assert_equal "v1", File.read(vendored("talon.rb"))
  end

  def test_a_failure_keeps_earlier_locks
    declare(%(github "asimmons91/talon", path: "lib"\ngithub "asimmons91/missing"\n))

    assert_raises(Deps::FetchError) { install }

    assert_equal ["github:asimmons91/talon/lib"], locks.map(&:key)
    declare(%(github "asimmons91/talon", path: "lib"\n))
    assert_equal [:unchanged], install.map(&:action)
  end

  def test_unknown_update_names
    declare(%(github "asimmons91/talon", path: "lib"\n))

    assert_raises(DrTalon::Error) { install(update: ["nope"]) }
  end

  def test_no_manifest_creates_nothing
    assert_empty install
    refute File.exist?(File.join(@root, "mygame", "dependencies.rb"))
  end

  def test_outdated_and_problems
    declare(%(github "asimmons91/talon", path: "lib"\nurl "https://x.test/easing.rb"\n))
    @context.http.files["https://x.test/easing.rb"] = "one"
    install
    installer = Deps::Installer.new(@project, context: @context)
    assert_empty installer.outdated
    assert_empty installer.problems

    v2 = commit_to(@remotes, "asimmons91", "talon", {"lib/talon.rb" => "v2"})
    outdated = installer.outdated
    assert_equal [["talon", @v1, v2]], outdated.map { |row| [row[:dependency].name, row[:locked], row[:latest]] }

    File.write(vendored("talon", "talon.rb"), "hacked")
    FileUtils.rm_f(vendored("easing.rb"))
    declare(%(github "asimmons91/talon", path: "lib"\nurl "https://x.test/easing.rb"\nurl "https://x.test/new.rb"\n))
    problems = installer.problems.map { |row| [row[:dependency].name, row[:problem]] }
    assert_equal [["talon", :modified], ["easing.rb", :missing], ["new.rb", :unlocked]], problems
  end
end
