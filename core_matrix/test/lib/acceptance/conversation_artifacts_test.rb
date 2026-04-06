require "test_helper"
require Rails.root.join("../acceptance/lib/conversation_artifacts")

class AcceptanceConversationArtifactsTest < ActiveSupport::TestCase
  test "conversation transcript markdown renders ordered messages" do
    markdown = Acceptance::ConversationArtifacts.conversation_transcript_markdown(
      "items" => [
        { "id" => "msg_1", "role" => "user", "content" => "Build 2048" },
        { "id" => "msg_2", "role" => "assistant", "content" => "Working on it" },
      ]
    )

    assert_includes markdown, "# Conversation Transcript"
    assert_includes markdown, "## Message 1"
    assert_includes markdown, "- Message `public_id`: `msg_1`"
    assert_includes markdown, "Build 2048"
    assert_includes markdown, "Working on it"
  end

  test "export roundtrip markdown summarizes transcript and export evidence" do
    markdown = Acceptance::ConversationArtifacts.export_roundtrip_markdown(
      source_conversation_id: "conv_source",
      imported_conversation_id: "conv_imported",
      supervision_trace: {
        "session" => { "conversation_supervision_session" => { "supervision_session_id" => "sup_1" } },
        "polls" => [{}, {}],
        "final_response" => { "machine_status" => { "overall_state" => "idle" } },
      },
      transcript_roundtrip_match: true,
      parsed_debug: {
        "command_runs.json" => [{}, {}],
        "process_runs.json" => [{}],
        "workflow_nodes.json" => [{}, {}, {}],
        "subagent_sessions.json" => [{}],
      }
    )

    assert_includes markdown, "Source conversation:"
    assert_includes markdown, "`conv_source`"
    assert_includes markdown, "`conv_imported`"
    assert_includes markdown, "transcript roundtrip match: `true`"
    assert_includes markdown, "command runs exported: `2`"
    assert_includes markdown, "workflow nodes exported: `3`"
  end
end
