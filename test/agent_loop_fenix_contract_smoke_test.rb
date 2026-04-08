require "json"
require "minitest/autorun"
require "open3"

class AgentLoopFenixContractSmokeTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CONTRACT_FIXTURE_PATH = File.join(
    ROOT,
    "shared",
    "fixtures",
    "contracts",
    "core_matrix_fenix_execution_assignment.json"
  )

  def test_core_matrix_and_fenix_accept_the_same_agent_loop_assignment_fixture
    fixture = JSON.parse(File.read(CONTRACT_FIXTURE_PATH))

    assert_equal "execution_assignment", fixture.fetch("item_type")
    assert_equal "program", fixture.fetch("control_plane")
    assert_equal "subagent_step", fixture.dig("payload", "task", "kind")
    assert_equal "gpt-5.4", fixture.dig("payload", "provider_context", "model_context", "model_ref")
    assert_equal true, fixture.dig("payload", "capability_projection", "is_subagent")
    assert_match(/public-id\z/, fixture.fetch("item_id"))
    assert_match(/public-id\z/, fixture.dig("payload", "task", "agent_task_run_id"))

    run_contract_test!(
      label: "core_matrix producer contract",
      chdir: File.join(ROOT, "core_matrix"),
      command: [
        "bin/rails",
        "test",
        "test/services/agent_control/create_execution_assignment_test.rb",
        "-i",
        "serializes the subagent execution assignment envelope that fenix consumes",
      ]
    )

    run_contract_test!(
      label: "fenix consumer contract",
      chdir: File.join(ROOT, "agents", "fenix"),
      command: [
        "bundle",
        "exec",
        "rails",
        "test",
        "test/integration/runtime_flow_test.rb",
        "-i",
        "shared core matrix execution assignment fixture preserves the real model and visible tool contract",
      ]
    )
  end

  private

  def run_contract_test!(label:, chdir:, command:)
    stdout, stderr, status = Open3.capture3({ "RAILS_ENV" => "test" }, *command, chdir: chdir)
    output = [stdout, stderr].reject(&:empty?).join("\n")

    assert status.success?, "#{label} failed:\n#{output}"
    assert_match(/\b1 runs\b/, output, "#{label} did not execute exactly one contract test:\n#{output}")
    assert_match(/0 failures, 0 errors/, output, "#{label} did not finish cleanly:\n#{output}")
  end
end
