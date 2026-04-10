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
require_relative 'artifact_bundle'
require_relative 'benchmark_reporting'
require_relative 'capability_activation'
require_relative 'credential_redaction'
require_relative 'capstone_app_api_roundtrip'
require_relative 'conversation_artifacts'
require_relative 'failure_classification'
require_relative 'host_validation'
require_relative 'live_progress_feed'
require_relative 'review_artifacts'
require_relative 'turn_runtime_transcript'
