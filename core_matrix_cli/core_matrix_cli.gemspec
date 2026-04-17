require_relative "lib/core_matrix_cli/version"

Gem::Specification.new do |spec|
  spec.name = "core_matrix_cli"
  spec.version = CoreMatrixCLI::VERSION
  spec.authors = ["jasl"]
  spec.email = ["jasl9187@hotmail.com"]

  spec.summary = "Operator CLI for CoreMatrix"
  spec.description = "Standalone operator CLI gem for CoreMatrix setup and readiness workflows."
  spec.homepage = "https://github.com/jasl/cybros"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.2"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.bindir = "exe"
  spec.executables = ["cmctl"]
  spec.require_paths = ["lib"]
  spec.files = Dir.glob("**/*", base: __dir__).reject do |f|
    File.directory?(File.join(__dir__, f)) ||
      (f == File.basename(__FILE__)) ||
      f.start_with?(
        *%w[Gemfile bin test docs tmp]
      ) ||
      (f.end_with?(".md") &&
        !%w[README.md].include?(f)
      )
  end

  spec.add_dependency "rqrcode", "~> 3.2"
  spec.add_dependency "thor", "~> 1.5"
end
