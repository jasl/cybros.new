# frozen_string_literal: true

require_relative "lib/cybros_nexus/version"

Gem::Specification.new do |spec|
  spec.name = "cybros_nexus"
  spec.version = CybrosNexus::VERSION
  spec.authors = ["jasl"]
  spec.email = ["jasl9187@hotmail.com"]

  spec.summary = "TODO: Write a short summary, because RubyGems requires one."
  spec.description = "TODO: Write a longer description or delete this line."
  spec.homepage = "https://github.com/jasl/cybros"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.2"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/jasl/cybros/tree/main/core_matrix_cli"
  spec.metadata["documentation_uri"] = "https://github.com/jasl/cybros/blob/main/core_matrix_cli/README.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/jasl/cybros/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.bindir = "exe"
  spec.executables = []
  spec.require_paths = ["lib"]
  spec.files = Dir.glob("**/*", base: __dir__).reject do |f|
    File.directory?(File.join(__dir__, f)) ||
      (f == File.basename(__FILE__)) ||
      f.start_with?(
        *%w[Gemfile bin test tmp]
      ) ||
      (f.end_with?(".md") &&
        !%w[README.md].include?(f)
      )
  end

  spec.add_dependency "thor", "~> 1.5"
end
