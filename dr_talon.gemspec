# frozen_string_literal: true

require_relative "lib/dr_talon/version"

Gem::Specification.new do |spec|
  spec.name = "dr_talon"
  spec.version = DrTalon::VERSION
  spec.authors = ["Austin Simmons"]
  spec.email = ["austin_simmons@fastmail.com"]

  spec.summary = "A Rails-style CLI for DragonRuby: engine versions, project scaffolding, and dependencies."
  spec.description = "talon manages cached DragonRuby Game Toolkit engines and pins them per project, scaffolds new games from templates, and vendors DragonRuby libraries with commit-locked dependencies."
  spec.homepage = "https://github.com/asimmons91/dr_talon"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  # spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .standard.yml PLAN.md])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
