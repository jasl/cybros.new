require_relative "../test_helper"

class RepoLicensingContractTest < Minitest::Test
  def test_only_core_matrix_remains_osaasy
    root_license = File.read("/Users/jasl/Workspaces/Ruby/cybros/LICENSE.md")
    fenix_license = File.read("/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/LICENSE.txt")
    nexus_license = File.read("/Users/jasl/Workspaces/Ruby/cybros/images/nexus/LICENSE.txt")
    core_matrix_license = File.read("/Users/jasl/Workspaces/Ruby/cybros/core_matrix/LICENSE.md")

    assert_includes root_license, "The MIT License (MIT)"
    assert_includes fenix_license, "The MIT License (MIT)"
    assert_includes nexus_license, "The MIT License (MIT)"
    assert_includes core_matrix_license, "O'Saasy License Agreement"
  end
end
