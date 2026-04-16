# frozen_string_literal: true

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../core_matrix/Gemfile', __dir__)
ENV['RAILS_ENV'] ||= 'development'

require 'bundler/setup'

# Shared path helpers and harness-only dependencies for acceptance scenarios.
module AcceptanceHarness
  module_function

  def acceptance_root
    @acceptance_root ||= Pathname.new(__dir__).join('..').expand_path
  end

  def repo_root
    @repo_root ||= acceptance_root.join('..').expand_path
  end
end

require_relative 'manual_support'
require_relative 'benchmark_reporting'
require_relative 'capstone_review_artifacts'
require_relative 'cli_support'
