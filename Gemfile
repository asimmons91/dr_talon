# frozen_string_literal: true

source "https://rubygems.org"

# CI installs this lockfile on every supported Ruby, back to 3.2, so resolve it
# there: newer releases of some development gems (rbs, parallel) need Ruby 3.3.
#   podman run --rm -v "$PWD":/app -w /app docker.io/library/ruby:3.2 bundle lock --update

# Specify your gem's dependencies in dr_talon.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "minitest", "~> 5.16"

gem "standard", "~> 1.3"
