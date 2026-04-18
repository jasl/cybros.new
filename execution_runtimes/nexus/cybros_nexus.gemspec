require_relative "lib/cybros_nexus/version"

Gem::Specification.new do |spec|
  spec.name = "cybros_nexus"
  spec.version = CybrosNexus::VERSION
  spec.authors = ["jasl"]
  spec.email = ["jasl9187@hotmail.com"]

  spec.summary = "Nexus execution runtime for the Cybros monorepo"
  spec.description = "CybrosNexus packages the Nexus execution runtime as a Ruby gem with a single nexus CLI entrypoint."
  spec.homepage = "https://github.com/jasl/cybros/tree/main/execution_runtimes/nexus"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.2"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["documentation_uri"] = "https://github.com/jasl/cybros/blob/main/execution_runtimes/nexus/README.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/jasl/cybros/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.bindir = "exe"
  spec.executables = ["nexus"]
  spec.require_paths = ["lib"]
  spec.files = Dir.glob("**/*", base: __dir__).reject do |f|
    File.directory?(File.join(__dir__, f)) ||
      (f == File.basename(__FILE__)) ||
      f.end_with?(".gem") ||
      f.start_with?(
        *%w[Gemfile bin test tmp]
      ) ||
      (f.end_with?(".md") &&
        !%w[README.md].include?(f)
      )
  end

  spec.add_dependency "thor", "~> 1.5"
  spec.add_dependency "sqlite3", "~> 2.9"
  spec.add_dependency "webrick", "~> 1.9"
  spec.add_dependency "websocket-client-simple", "~> 0.9"
  spec.add_dependency "logger", "~> 1.7"
end
