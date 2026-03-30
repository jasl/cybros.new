require "test_helper"
require "tmpdir"
require Rails.root.join("script/manual/workflow_proof_export").to_s

class WorkflowProofExportFlowTest < ActionDispatch::IntegrationTest
  test "manual export writes one mermaid artifact and one proof record for a workflow public id" do
    fixture = build_workflow_proof_fixture!

    Dir.mktmpdir("workflow-proof-export") do |dir|
      stdout = StringIO.new
      stderr = StringIO.new

      exit_code = WorkflowProofExport.run(
        [
          "export",
          "--workflow-run-id=#{fixture.fetch(:workflow_run).public_id}",
          "--scenario=acceptance-proof-export",
          "--out=#{dir}",
        ],
        stdout: stdout,
        stderr: stderr
      )

      assert_equal 0, exit_code, stderr.string
      assert_equal "", stderr.string
      assert File.exist?(File.join(dir, "proof.md"))
      assert File.exist?(File.join(dir, "run-#{fixture.fetch(:workflow_run).public_id}.mmd"))
      assert_includes File.read(File.join(dir, "proof.md")), "# acceptance-proof-export"
    end
  end

  test "manual export refuses to overwrite an existing proof package without force" do
    fixture = build_workflow_proof_fixture!

    Dir.mktmpdir("workflow-proof-export") do |dir|
      first_stdout = StringIO.new
      first_stderr = StringIO.new
      first_exit_code = WorkflowProofExport.run(
        [
          "export",
          "--workflow-run-id=#{fixture.fetch(:workflow_run).public_id}",
          "--scenario=acceptance-proof-export",
          "--out=#{dir}",
        ],
        stdout: first_stdout,
        stderr: first_stderr
      )

      second_stdout = StringIO.new
      second_stderr = StringIO.new
      second_exit_code = WorkflowProofExport.run(
        [
          "export",
          "--workflow-run-id=#{fixture.fetch(:workflow_run).public_id}",
          "--scenario=acceptance-proof-export",
          "--out=#{dir}",
        ],
        stdout: second_stdout,
        stderr: second_stderr
      )

      assert_equal 0, first_exit_code, first_stderr.string
      assert_equal 1, second_exit_code
      assert_includes second_stderr.string, "Refusing to overwrite existing proof artifacts"
    end
  end
end
