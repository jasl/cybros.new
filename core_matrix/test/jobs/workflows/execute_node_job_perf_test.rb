require "test_helper"

class Workflows::ExecuteNodeJobPerfTest < ActiveSupport::TestCase
  test "publishes queue delay event when execute node job starts" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    queue_events = []

    freeze_time do
      workflow_node.update!(
        lifecycle_state: "completed",
        started_at: 5.seconds.ago,
        finished_at: 4.seconds.ago
      )

      ActiveSupport::Notifications.subscribed(->(*args) { queue_events << args.last }, "perf.workflows.execute_node_queue_delay") do
        Workflows::ExecuteNodeJob.perform_now(
          workflow_node.public_id,
          enqueued_at_iso8601: 1.5.seconds.ago.iso8601(6),
          queue_name: "workflow_default"
        )
      end
    end

    assert_equal 1, queue_events.length
    assert_equal workflow_node.public_id, queue_events.first.fetch("workflow_node_public_id")
    assert_equal workflow_node.workspace.public_id, queue_events.first.fetch("workspace_public_id")
    assert_equal workflow_node.conversation.public_id, queue_events.first.fetch("conversation_public_id")
    assert_equal workflow_node.turn.public_id, queue_events.first.fetch("turn_public_id")
    assert_equal workflow_node.conversation.agent_program.public_id, queue_events.first.fetch("agent_program_public_id")
    assert_equal "workflow_default", queue_events.first.fetch("queue_name")
    assert_operator queue_events.first.fetch("queue_delay_ms"), :>=, 1500.0
  end
end
