require_relative "../pure_test_helper"

class VerificationCoreMatrixHostedLaneContractTest < Minitest::Test
  def test_core_matrix_hosted_test_script_prepares_test_database
    script = VerificationPureTestHelper.verification_root.join("bin", "test_core_matrix_hosted.sh").read

    assert_includes script, "bin/rails db:test:prepare"
    assert_operator script.index("bin/rails db:test:prepare"), :<, script.index("bundle exec ruby ../verification/test/core_matrix_hosted_runner.rb")
  end
end
