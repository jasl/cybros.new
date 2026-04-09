require "test_helper"

class TurnExecutionSnapshotTest < ActiveSupport::TestCase
  test "builds runtime_context with public agent program and user ids" do
    context = build_agent_control_context!

    snapshot = TurnExecutionSnapshot.new(turn: context.fetch(:turn))

    assert_equal(
      {
        "control_plane" => "program",
        "agent_program_version_id" => context.fetch(:deployment).public_id,
        "agent_program_id" => context.fetch(:agent_program).public_id,
        "user_id" => context.fetch(:user).public_id,
        "executor_program_id" => context.fetch(:executor_program).public_id,
      },
      snapshot.runtime_context.compact
    )
  end

  test "returns deep-duped hashes and arrays while defaulting missing sections" do
    snapshot = TurnExecutionSnapshot.new(
      payload: {
        "identity" => { "turn_id" => "turn-1" },
        "task" => { "turn_id" => "turn-1" },
        "conversation_projection" => { "messages" => [{ "role" => "user", "content" => "hello" }], "context_imports" => [], "prior_tool_results" => [] },
        "capability_projection" => { "tool_surface" => [{ "tool_name" => "exec_command" }] },
        "provider_context" => {
          "provider_execution" => {},
          "budget_hints" => {},
          "model_context" => { "provider_handle" => "openai" },
        },
        "attachment_manifest" => [{ "attachment_id" => "att-1" }],
      }
    )

    identity = snapshot.identity
    conversation_projection = snapshot.conversation_projection
    attachments = snapshot.attachment_manifest
    identity["turn_id"] = "mutated"
    conversation_projection["messages"].first["content"] = "mutated"
    attachments.clear

    assert_equal({ "turn_id" => "turn-1" }, snapshot.identity)
    assert_equal([{ "role" => "user", "content" => "hello" }], snapshot.conversation_projection.fetch("messages"))
    assert_equal([{ "attachment_id" => "att-1" }], snapshot.attachment_manifest)
    assert_equal({ "provider_handle" => "openai" }, snapshot.model_context)
    assert_equal({ "provider_execution" => {}, "budget_hints" => {}, "model_context" => { "provider_handle" => "openai" } }, snapshot.provider_context)
    assert_equal({ "turn_id" => "turn-1" }, snapshot.task)
    assert_equal({ "tool_surface" => [{ "tool_name" => "exec_command" }] }, snapshot.capability_projection)
    assert_equal([], snapshot.model_input_attachments)
    assert_equal([], snapshot.attachment_diagnostics)
  end

  test "requires either a turn or an explicit payload" do
    error = assert_raises(ArgumentError) do
      TurnExecutionSnapshot.new
    end

    assert_match(/turn or payload/i, error.message)
  end
end
