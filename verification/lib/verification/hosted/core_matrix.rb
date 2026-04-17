# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "development"

require_relative "../boot"
require Verification::Adapters::CoreMatrix.environment_path
require_relative "../support/governed_validation_support"
require_relative "../suites/e2e/manual_support"
require_relative "../suites/proof/capstone_review_artifacts"
