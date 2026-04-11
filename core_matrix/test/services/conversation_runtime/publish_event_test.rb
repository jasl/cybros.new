require "test_helper"
require "action_cable/test_helper"

class ConversationRuntime::PublishEventTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "broadcasts and projects workflow node runtime events with a replaceable stream key" do
    context = build_runtime_context!
    stream_name = ConversationRuntime::StreamName.for_conversation(context.fetch(:conversation))

    broadcasts = capture_broadcasts(stream_name) do
      ConversationRuntime::PublishEvent.call(
        conversation: context.fetch(:conversation),
        turn: context.fetch(:turn),
        event_kind: "runtime.workflow_node.started",
        payload: {
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "state" => "running",
        }
      )

      ConversationRuntime::PublishEvent.call(
        conversation: context.fetch(:conversation),
        turn: context.fetch(:turn),
        event_kind: "runtime.workflow_node.completed",
        payload: {
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
          "state" => "completed",
        }
      )
    end

    assert_equal ["runtime.workflow_node.started", "runtime.workflow_node.completed"], broadcasts.map { |payload| payload.fetch("event_kind") }

    runtime_projection = ConversationEvent.live_projection(conversation: context.fetch(:conversation))
      .select { |event| event.event_kind.start_with?("runtime.workflow_node.") }

    assert_equal 1, runtime_projection.length
    assert_equal "runtime.workflow_node.completed", runtime_projection.first.event_kind
    assert_equal context.fetch(:workflow_node).public_id, runtime_projection.first.payload.fetch("workflow_node_id")
    assert_equal context.fetch(:workflow_run).public_id, runtime_projection.first.payload.fetch("workflow_run_id")
  end

  test "broadcasts process run output but does not persist raw output chunks" do
    context = build_runtime_context!
    process_run = create_process_run!(
      conversation: context.fetch(:conversation),
      turn: context.fetch(:turn),
      workflow_node: context.fetch(:workflow_node),
      execution_runtime: context.fetch(:execution_runtime)
    )
    stream_name = ConversationRuntime::StreamName.for_conversation(process_run.conversation)

    broadcasts = capture_broadcasts(stream_name) do
      ConversationRuntime::PublishEvent.call(
        conversation: process_run.conversation,
        turn: process_run.turn,
        event_kind: "runtime.process_run.output",
        payload: {
          "process_run_id" => process_run.public_id,
          "kind" => process_run.kind,
          "lifecycle_state" => process_run.lifecycle_state,
          "stream" => "stdout",
          "text" => "hello world",
        }
      )
    end

    assert_equal ["runtime.process_run.output"], broadcasts.map { |payload| payload.fetch("event_kind") }
    assert_equal "hello world", broadcasts.first.dig("payload", "text")

    projection = ConversationEvent.live_projection(conversation: process_run.conversation)
      .select { |event| event.event_kind == "runtime.process_run.output" }

    assert_equal 1, projection.length
    assert_equal process_run.public_id, projection.first.payload.fetch("process_run_id")
    refute_includes projection.first.payload.keys, "text"
  end

  private

  def build_runtime_context!
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context.fetch(:workspace),
      execution_runtime: context.fetch(:execution_runtime),
      agent_snapshot: context.fetch(:agent_snapshot)
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Runtime event input",
      agent_snapshot: context.fetch(:agent_snapshot),
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run, metadata: {})

    context.merge(
      conversation: conversation,
      turn: turn,
      workflow_run: workflow_run,
      workflow_node: workflow_node
    )
  end
end
