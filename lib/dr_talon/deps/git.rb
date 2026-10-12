# frozen_string_literal: true

require "fileutils"
require "open3"

module DrTalon
  module Deps
    # Runs the git CLI, for resolving refs and fetching git dependencies.
    class Git
      FULL_SHA = /\A\h{40}\z/

      # Resolves +ref+ (a branch, tag or full commit SHA; nil for the default
      # branch) to a commit SHA without cloning.
      #
      # @param url [String]
      # @param ref [String, nil]
      # @return [String]
      # @raise [FetchError]
      def resolve(url, ref)
        return ref.downcase if ref&.match?(FULL_SHA)

        refs = ls_remote(url).to_h { |line| line.split("\t", 2).reverse }
        candidates =
          if ref.nil?
            ["HEAD"]
          else
            ["refs/tags/#{ref}^{}", "refs/tags/#{ref}", "refs/heads/#{ref}"]
          end
        sha = candidates.filter_map { |name| refs[name] }.first
        return sha if sha

        hint = ref&.match?(/\A\h{4,39}\z/) ? " Abbreviated SHAs aren't supported; use all 40 characters." : ""
        raise FetchError, "#{url} has no branch or tag named #{ref.inspect}.#{hint}"
      end

      # Checks out +commit+ of +url+ into +dir+ (which must not exist).
      #
      # @return [void]
      # @raise [FetchError]
      def checkout(url, commit, dir)
        run("init", "--quiet", dir)
        run("-C", dir, "fetch", "--quiet", "--depth", "1", url, commit)
        run("-C", dir, "-c", "advice.detachedHead=false", "checkout", "--quiet", "FETCH_HEAD")
      rescue FetchError
        # Some servers don't allow fetching an arbitrary commit; fall back to a
        # full clone.
        FileUtils.rm_rf(dir)
        run("clone", "--quiet", "--no-checkout", url, dir)
        run("-C", dir, "-c", "advice.detachedHead=false", "checkout", "--quiet", commit)
      end

      private

      def ls_remote(url)
        run("ls-remote", url).lines(chomp: true)
      end

      def run(*args)
        out, err, status = Open3.capture3("git", *args)
        # git's first line says what went wrong; the rest is generic advice.
        raise FetchError, "git #{args.first} failed: #{err.lines.map(&:strip).find { |l| !l.empty? }}" unless status.success?

        out
      rescue Errno::ENOENT
        raise FetchError, "git isn't installed; it's needed for git and GitHub dependencies."
      end
    end
  end
end
