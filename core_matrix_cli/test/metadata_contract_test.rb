require "test_helper"

class MetadataContractTest < CoreMatrixCLITestCase
  def test_gemspec_and_readme_are_real_product_metadata
    readme = File.read(File.expand_path("../README.md", __dir__))
    gemspec = Gem::Specification.load(File.expand_path("../core_matrix_cli.gemspec", __dir__))

    refute_includes readme, "TODO:"
    refute_includes readme, "bin/cmctl"
    assert_includes readme, "bundle exec exe/cmctl"
    assert_equal "MIT", gemspec.license
    assert_equal ["cmctl"], gemspec.executables
    assert_equal "https://github.com/jasl/cybros", gemspec.homepage
    assert_equal "https://github.com/jasl/cybros/tree/main/core_matrix_cli", gemspec.metadata["source_code_uri"]
    assert_equal "https://github.com/jasl/cybros/blob/main/core_matrix_cli/README.md", gemspec.metadata["documentation_uri"]
    refute_match(/TODO/i, gemspec.summary)
  end
end
