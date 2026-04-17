require_relative "../test_helper"

class RepoLicensingContractTest < Minitest::Test
  def test_only_core_matrix_remains_osaasy
    repo_root = Verification.repo_root
    root_license = File.read(repo_root.join("LICENSE.md"))
    fenix_license = File.read(repo_root.join("agents", "fenix", "LICENSE.txt"))
    nexus_license = File.read(repo_root.join("images", "nexus", "LICENSE.txt"))
    core_matrix_license = File.read(repo_root.join("core_matrix", "LICENSE.md"))

    assert_includes root_license, "The MIT License (MIT)"
    assert_includes fenix_license, "The MIT License (MIT)"
    assert_includes nexus_license, "The MIT License (MIT)"
    assert_includes core_matrix_license, "O'Saasy License Agreement"
  end
end
