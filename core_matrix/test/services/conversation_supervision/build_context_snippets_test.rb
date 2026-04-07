require "test_helper"

class ConversationSupervision::BuildContextSnippetsTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "extracts reusable context snippets instead of heuristic fact summaries" do
    fixture = prepare_conversation_supervision_context!

    payload = ConversationSupervision::BuildContextSnippets.call(
      conversation: fixture.fetch(:conversation),
      limit: 8
    )

    snippets = payload.fetch("context_snippets")

    assert snippets.any? { |snippet| snippet.fetch("excerpt").match?(/2048 acceptance flow|adding tests/i) }
    assert snippets.all? { |snippet| snippet.fetch("message_id").present? && snippet.fetch("role").present? }
    refute_includes payload.to_json, "Context already references"
  end
end
