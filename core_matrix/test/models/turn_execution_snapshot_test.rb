require "test_helper"

class TurnExecutionSnapshotTest < ActiveSupport::TestCase
  test "returns deep-duped hashes and arrays while defaulting missing sections" do
    snapshot = TurnExecutionSnapshot.new(
      "identity" => { "turn_id" => "turn-1" },
      "context_messages" => [{ "role" => "user", "content" => "hello" }],
      "attachment_manifest" => [{ "attachment_id" => "att-1" }],
      "provider_execution" => { "provider_handle" => "openai" }
    )

    identity = snapshot.identity
    messages = snapshot.context_messages
    attachments = snapshot.attachment_manifest
    identity["turn_id"] = "mutated"
    messages.first["content"] = "mutated"
    attachments.clear

    assert_equal({ "turn_id" => "turn-1" }, snapshot.identity)
    assert_equal([{ "role" => "user", "content" => "hello" }], snapshot.context_messages)
    assert_equal([{ "attachment_id" => "att-1" }], snapshot.attachment_manifest)
    assert_equal({ "provider_handle" => "openai" }, snapshot.provider_execution)
    assert_equal({}, snapshot.agent_context)
    assert_equal([], snapshot.runtime_attachment_manifest)
  end
end
