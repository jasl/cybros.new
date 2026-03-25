require "test_helper"

class Workflows::IntentBatchMaterializationTest < ActiveSupport::TestCase
  test "materializes accepted intents and batch summaries onto workflow-owned rows" do
    context = prepare_workflow_execution_context!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "agent_step_1",
      root_node_type: "agent_task_run",
      decision_source: "agent_program",
      metadata: {}
    )
    yielding_node = workflow_run.workflow_nodes.first

    result = Workflows::IntentBatchMaterialization.call(
      workflow_run: workflow_run,
      yielding_node: yielding_node,
      batch_manifest: {
        "batch_id" => "batch-1",
        "resume_policy" => "re_enter_agent",
        "successor" => {
          "node_key" => "agent_step_2",
          "node_type" => "agent_task_run",
        },
        "stages" => [
          {
            "stage_index" => 0,
            "dispatch_mode" => "serial",
            "completion_barrier" => "wait_all",
            "intents" => [
              {
                "intent_id" => "intent-1",
                "intent_kind" => "conversation_title_update",
                "node_key" => "title-update",
                "node_type" => "conversation_title_update",
                "requirement" => "required",
                "conflict_scope" => "conversation_metadata",
                "presentation_policy" => "internal_only",
                "durable_outcome" => "accepted",
                "payload" => { "title" => "Retitled" },
                "idempotency_key" => "intent-1",
              },
            ],
          },
        ],
      }
    )

    accepted_node = workflow_run.reload.workflow_nodes.find_by!(node_key: "title-update")
    batch_manifest = workflow_run.workflow_artifacts.find_by!(artifact_kind: "intent_batch_manifest")
    barrier_summary = workflow_run.workflow_artifacts.find_by!(artifact_kind: "intent_batch_barrier")
    yield_event = workflow_run.workflow_node_events.find_by!(
      workflow_node: yielding_node,
      event_kind: "yield_requested"
    )

    assert_equal [accepted_node], result.accepted_nodes
    assert_equal "re_enter_agent", workflow_run.resume_policy
    assert_equal "batch-1", workflow_run.resume_metadata["batch_id"]
    assert_equal "agent_step_2", workflow_run.resume_metadata.dig("successor", "node_key")
    assert_equal yielding_node, accepted_node.yielding_workflow_node
    assert_equal 0, accepted_node.stage_index
    assert_equal 0, accepted_node.stage_position
    assert_equal "conversation_title_update", accepted_node.intent_kind
    assert_equal "batch-1", batch_manifest.payload["batch_id"]
    assert_equal "wait_all", barrier_summary.payload.dig("stage", "completion_barrier")
    assert_equal "batch-1", yield_event.payload["batch_id"]
  end

  test "records rejected intents as audit-only workflow node events without durable mutation nodes" do
    context = prepare_workflow_execution_context!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "agent_step_1",
      root_node_type: "agent_task_run",
      decision_source: "agent_program",
      metadata: {}
    )
    yielding_node = workflow_run.workflow_nodes.first

    Workflows::IntentBatchMaterialization.call(
      workflow_run: workflow_run,
      yielding_node: yielding_node,
      batch_manifest: {
        "batch_id" => "batch-2",
        "resume_policy" => "re_enter_agent",
        "stages" => [
          {
            "stage_index" => 0,
            "dispatch_mode" => "parallel",
            "completion_barrier" => "wait_all",
            "intents" => [
              {
                "intent_id" => "intent-rejected",
                "intent_kind" => "subagent_spawn",
                "node_key" => "subagent-1",
                "node_type" => "subagent_spawn",
                "requirement" => "best_effort",
                "conflict_scope" => "subagent_pool",
                "presentation_policy" => "ops_trackable",
                "durable_outcome" => "rejected",
                "rejection_reason" => "parallel_conflict",
                "payload" => { "agent" => "fenix-helper" },
                "idempotency_key" => "intent-rejected",
              },
            ],
          },
        ],
      }
    )

    rejection_event = workflow_run.workflow_node_events.find_by!(
      workflow_node: yielding_node,
      event_kind: "intent_rejected"
    )

    assert_nil workflow_run.workflow_nodes.find_by(node_key: "subagent-1")
    assert_equal "intent-rejected", rejection_event.payload["intent_id"]
    assert_equal "parallel_conflict", rejection_event.payload["reason"]
  end
end
