# frozen_string_literal: true

require 'bundler/setup'
require 'pathname'
require "active_support/core_ext/object/blank"

# Shared path helpers and harness-only dependencies for verification scenarios.
module Verification
  module_function

  def verification_root
    @verification_root ||= Pathname.new(__dir__).join('..', '..').expand_path
  end

  def repo_root
    @repo_root ||= verification_root.join('..').expand_path
  end
end

require_relative 'active_suite'
require_relative 'adapters/core_matrix'
require_relative 'adapters/core_matrix_cli'
require_relative 'adapters/fenix'
require_relative 'adapters/nexus'
require_relative 'suites/e2e/conversation_runtime_validation'
require_relative 'suites/perf/benchmark_reporting'
require_relative 'support/cli_support'
require_relative 'support/host_validation'
