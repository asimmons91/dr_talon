# frozen_string_literal: true

require "date"

# Release flow (the first release is release:prepare[0.1.0], the untagged current version):
#   1. bundle exec rake release:prepare[minor]   # or major, patch, X.Y.Z
#   2. git push origin main vX.Y.Z               # .github/workflows/release.yml publishes it
module Release
  ROOT = File.expand_path("..", __dir__)
  VERSION_FILE = File.join(ROOT, "lib/dr_talon/version.rb")
  CHANGELOG = File.join(ROOT, "CHANGELOG.md")
  REPO_URL = "https://github.com/asimmons91/dr_talon"
  UNRELEASED = "## [Unreleased]"

  module_function

  # Read from disk rather than the VERSION constant, which Bundler's gem tasks
  # have already loaded.
  def current_version
    File.read(VERSION_FILE)[/VERSION = "([^"]+)"/, 1] or abort "No VERSION in #{VERSION_FILE}"
  end

  # @param bump [String] "major", "minor", "patch", or an explicit version
  def next_version(bump)
    major, minor, patch = Gem::Version.new(current_version).segments
    case bump
    when "major" then "#{major + 1}.0.0"
    when "minor" then "#{major}.#{minor + 1}.0"
    when "patch" then "#{major}.#{minor}.#{patch.to_i + 1}"
    when /\A\d+\.\d+\.\d+(\.[0-9A-Za-z.]+)?\z/ then bump
    else abort "Expected major, minor, patch, or a version like 1.2.3 (got #{bump.inspect})"
    end
  end

  # The body of a changelog section (without its heading), or nil.
  def section(heading_prefix)
    lines = File.read(CHANGELOG).lines
    start = lines.index { |line| line.start_with?(heading_prefix) } or return nil
    stop = (start + 1...lines.length).find { |i| lines[i].start_with?("## ", "[") } || lines.length
    lines[start + 1...stop].join.strip
  end

  def notes(version)
    section("## [#{version}]")
  end

  # Moves the Unreleased notes under a dated heading for `version` and
  # updates the compare links at the bottom of the changelog.
  def date_changelog(version, previous)
    text = File.read(CHANGELOG)
    text.sub!("#{UNRELEASED}\n", "#{UNRELEASED}\n\n## [#{version}] - #{Date.today.iso8601}\n") or
      abort "#{CHANGELOG} has no #{UNRELEASED.inspect} heading"

    # Link references go at the end: Unreleased, then newest to oldest.
    links = text.scan(/^\[[^\]]+\]: \S+\n/)
    links.each { |link| text.sub!(link, "") }
    links.reject! { |link| link.start_with?("[Unreleased]:") }
    version_link = if tag_exists?("v#{previous}")
      "#{REPO_URL}/compare/v#{previous}...v#{version}"
    else
      "#{REPO_URL}/releases/tag/v#{version}"
    end
    links.unshift("[Unreleased]: #{REPO_URL}/compare/v#{version}...HEAD\n", "[#{version}]: #{version_link}\n")
    File.write(CHANGELOG, "#{text.rstrip}\n\n#{links.join}")
  end

  def bump_version_file(version)
    text = File.read(VERSION_FILE)
    File.write(VERSION_FILE, text.sub(/VERSION = "[^"]+"/, %(VERSION = "#{version}")))
  end

  def git(*args)
    out = IO.popen(["git", "-C", ROOT, *args], err: File::NULL, &:read)
    [out.strip, $?.success?]
  end

  def tag_exists?(tag)
    git("rev-parse", "--verify", "--quiet", "refs/tags/#{tag}")[1]
  end

  def guard_repo(tag)
    branch, = git("rev-parse", "--abbrev-ref", "HEAD")
    abort "Release from main (on #{branch})" unless branch == "main"
    abort "Commit or stash your changes first" unless git("status", "--porcelain")[0].empty?
    abort "Tag #{tag} already exists" if tag_exists?(tag)

    git("fetch", "--quiet", "origin", "main")
    behind, = git("rev-list", "--count", "HEAD..origin/main")
    abort "main is #{behind} commit(s) behind origin/main; pull first" unless behind == "0"
  end
end

namespace :release do
  desc "Bump the version, date the changelog's Unreleased notes, then commit and tag (major, minor, patch, or X.Y.Z)"
  task :prepare, [:bump] do |_task, args|
    previous = Release.current_version
    version = Release.next_version(args[:bump] || abort("Usage: rake release:prepare[major|minor|patch|X.Y.Z]"))
    tag = "v#{version}"
    # The current version can be released as is if it was never tagged, as
    # with the first release (rake release:prepare[0.1.0]).
    unreleased = version == previous && !Release.tag_exists?("v#{previous}")
    unless unreleased || Gem::Version.new(version) > Gem::Version.new(previous)
      abort "#{version} is not newer than #{previous}"
    end

    Release.guard_repo(tag)
    abort "The #{Release::UNRELEASED} section of CHANGELOG.md is empty" if Release.section(Release::UNRELEASED).to_s.empty?

    Rake::Task[:default].invoke

    Release.bump_version_file(version)
    Release.date_changelog(version, previous)
    sh "bundle", "lock", "--local"

    sh "git", "-C", Release::ROOT, "add", Release::VERSION_FILE, Release::CHANGELOG, "Gemfile.lock"
    sh "git", "-C", Release::ROOT, "commit", "--quiet", "-m", "Release #{tag}"
    sh "git", "-C", Release::ROOT, "tag", "--annotate", tag, "-m", tag

    puts <<~MSG

      Prepared #{tag} (was v#{previous}). Review it with `git show #{tag}`, then publish with:

        git push origin main #{tag}

      To undo before pushing: git tag -d #{tag} && git reset --hard HEAD~1
    MSG
  end

  desc "Print the changelog notes for a version (default: the current version)"
  task :notes, [:version] do |_task, args|
    version = args[:version] || Release.current_version
    puts Release.notes(version) || abort("CHANGELOG.md has no section for #{version}")
  end

  desc "Check that a release tag (default: $GITHUB_REF_NAME) matches the version and has changelog notes"
  task :check, [:tag] do |_task, args|
    tag = args[:tag] || ENV["GITHUB_REF_NAME"] || abort("Usage: rake release:check[vX.Y.Z]")
    version = Release.current_version
    abort "Tag #{tag} doesn't match version.rb (#{version})" unless tag == "v#{version}"
    abort "CHANGELOG.md has no notes for #{version}" if Release.notes(version).to_s.empty?
    puts "#{tag} matches version.rb and has changelog notes"
  end
end
