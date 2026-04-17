require_relative "../pure_test_helper"

class VerificationCoreMatrixHostedLaneContractTest < Minitest::Test
  def test_core_matrix_hosted_test_script_prepares_test_database
    script = VerificationPureTestHelper.verification_root.join("bin", "test_core_matrix_hosted.sh").read

    assert_includes script, "bin/rails db:test:prepare"
    assert_operator script.index("bin/rails db:test:prepare"), :<, script.index("bundle exec ruby ../verification/test/core_matrix_hosted_runner.rb")
  end

  def test_root_ci_provisions_postgres_for_core_matrix_hosted_lane
    workflow = VerificationPureTestHelper.repo_root.join(".github", "workflows", "ci.yml").read
    hosted_job = workflow.split(/^  verification_core_matrix_hosted_test:\n/, 2).last

    refute_nil hosted_job, "expected verification_core_matrix_hosted_test job in root CI workflow"
    assert_includes hosted_job, "services:"
    assert_includes hosted_job, "postgres:"
    assert_includes hosted_job, "image: postgres:18"
    assert_includes hosted_job, "DATABASE_URL: postgres://postgres:postgres@localhost:5432"
  end
end
