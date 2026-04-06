ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
ENV["RAILS_ENV"] ||= "development"

require "bundler/setup"
require "pathname"

module AcceptanceHarness
  module_function

  def acceptance_root
    @acceptance_root ||= Pathname.new(__dir__).join("..").expand_path
  end

  def repo_root
    @repo_root ||= acceptance_root.join("..").expand_path
  end
end

require_relative "../../core_matrix/script/manual/manual_acceptance_support"
require_relative "capability_activation"
require_relative "failure_classification"
require_relative "turn_runtime_transcript"
