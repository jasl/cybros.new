require "test_helper"

class ConversationSupervision::BuildRuntimeEvidenceTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "captures generic runtime evidence without inferring business semantics" do
    fixture = prepare_provider_backed_conversation_supervision_context!

    payload = ConversationSupervision::BuildRuntimeEvidence.call(
      conversation: fixture.fetch(:conversation),
      workflow_run: fixture.fetch(:workflow_run)
    )

    assert_equal fixture.fetch(:active_command_run).public_id,
      payload.dig("active_command", "command_run_public_id")
    assert_equal "/workspace/game-2048", payload.dig("active_command", "cwd")
    assert_equal "npm test && npm run build", payload.dig("active_command", "command_preview")
    refute_match(/React app|game files|test-and-build check|preview server|npm install -g/i, payload.to_json)
  end
end
