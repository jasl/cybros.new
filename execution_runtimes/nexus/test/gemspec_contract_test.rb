require "test_helper"
require "rubygems"

class GemspecContractTest < Minitest::Test
  def test_gemspec_files_exclude_built_gem_archives
    spec = Gem::Specification.load(File.expand_path("../cybros_nexus.gemspec", __dir__))

    refute_nil spec
    refute spec.files.any? { |path| path.end_with?(".gem") }
  end

  def test_gemspec_declares_logger_runtime_dependency
    spec = Gem::Specification.load(File.expand_path("../cybros_nexus.gemspec", __dir__))

    refute_nil spec
    assert_includes spec.runtime_dependencies.map(&:name), "logger"
  end
end
