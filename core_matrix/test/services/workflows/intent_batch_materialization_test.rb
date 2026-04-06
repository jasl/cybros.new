require "test_helper"

class Workflows::IntentBatchMaterializationTest < ActiveSupport::TestCase
  setup do
    truncate_all_tables!
  end

  test "materializes accepted intents and batch summaries onto workflow-owned rows" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_program_version: context[:agent_program_version],
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
                "intent_kind" => "ops_annotation",
                "node_key" => "ops-annotation-1",
                "node_type" => "ops_annotation",
                "requirement" => "required",
                "conflict_scope" => "workflow_annotation",
                "presentation_policy" => "internal_only",
                "durable_outcome" => "accepted",
                "payload" => { "note" => "Retitled" },
                "idempotency_key" => "intent-1",
              },
            ],
          },
        ],
      }
    )

    accepted_node = workflow_run.reload.workflow_nodes.find_by!(node_key: "ops-annotation-1")
    batch_manifest = workflow_run.workflow_artifacts.find_by!(artifact_kind: "intent_batch_manifest")
    barrier_summary = workflow_run.workflow_artifacts.find_by!(artifact_kind: "intent_batch_barrier")
    yield_event = workflow_run.workflow_node_events.find_by!(
      workflow_node: yielding_node,
      event_kind: "yield_requested"
    )

    assert_equal [accepted_node], result.accepted_nodes
    assert_equal "re_enter_agent", workflow_run.resume_policy
    assert_equal "batch-1", workflow_run.resume_batch_id
    assert_equal yielding_node, workflow_run.resume_yielding_workflow_node
    assert_equal "agent_step_2", workflow_run.resume_successor_node_key
    assert_equal "agent_task_run", workflow_run.resume_successor_node_type
    assert_equal yielding_node, accepted_node.yielding_workflow_node
    assert_equal 0, accepted_node.stage_index
    assert_equal 0, accepted_node.stage_position
    assert_equal "ops_annotation", accepted_node.intent_kind
    assert_equal "batch-1", accepted_node.intent_batch_id
    assert_equal "intent-1", accepted_node.intent_id
    assert_equal "required", accepted_node.intent_requirement
    assert_equal "workflow_annotation", accepted_node.intent_conflict_scope
    assert_equal "intent-1", accepted_node.intent_idempotency_key
    assert_equal({ "note" => "Retitled" }, accepted_node.intent_payload)
    refute accepted_node.metadata.key?("payload")
    refute accepted_node.metadata.key?("intent_kind")
    refute accepted_node.metadata.key?("idempotency_key")
    assert_equal "batch-1", batch_manifest.payload["batch_id"]
    assert_equal 1, batch_manifest.payload["accepted_intent_count"]
    assert_equal 0, batch_manifest.payload["rejected_intent_count"]
    assert_equal yielding_node.node_key, batch_manifest.workflow_node_key
    assert_equal "wait_all", barrier_summary.payload.dig("stage", "completion_barrier")
    assert_equal "batch-1", yield_event.payload["batch_id"]
    assert_equal ["ops-annotation-1"], yield_event.payload["accepted_node_keys"]
    assert_equal [barrier_summary.artifact_key], yield_event.payload["barrier_artifact_keys"]
  end

  test "records rejected intents as audit-only workflow node events without durable mutation nodes" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_program_version: context[:agent_program_version],
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
    refute rejection_event.payload.key?("payload")
  end

  test "materializes multi-stage batches while only creating barrier artifacts for blocking stages" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_program_version: context[:agent_program_version],
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
        "batch_id" => "batch-3",
        "resume_policy" => "re_enter_agent",
        "stages" => [
          {
            "stage_index" => 0,
            "dispatch_mode" => "serial",
            "completion_barrier" => "none",
            "intents" => [
              {
                "intent_id" => "intent-accepted-1",
                "intent_kind" => "ops_annotation",
                "node_key" => "ops-annotation-1",
                "node_type" => "ops_annotation",
                "requirement" => "required",
                "conflict_scope" => "workflow_annotation",
                "presentation_policy" => "internal_only",
                "durable_outcome" => "accepted",
                "payload" => { "note" => "Stage one" },
                "idempotency_key" => "intent-accepted-1",
              },
              {
                "intent_id" => "intent-rejected-1",
                "intent_kind" => "subagent_spawn",
                "node_key" => "subagent-stage-1",
                "node_type" => "subagent_spawn",
                "requirement" => "best_effort",
                "conflict_scope" => "subagent_pool",
                "presentation_policy" => "ops_trackable",
                "durable_outcome" => "rejected",
                "rejection_reason" => "parallel_conflict",
                "payload" => { "agent" => "fenix-helper" },
                "idempotency_key" => "intent-rejected-1",
              },
            ],
          },
          {
            "stage_index" => 1,
            "dispatch_mode" => "parallel",
            "completion_barrier" => "wait_all",
            "intents" => [
              {
                "intent_id" => "intent-accepted-2",
                "intent_kind" => "ops_annotation",
                "node_key" => "ops-annotation-2",
                "node_type" => "ops_annotation",
                "requirement" => "required",
                "conflict_scope" => "workflow_annotation",
                "presentation_policy" => "internal_only",
                "durable_outcome" => "accepted",
                "payload" => { "note" => "Stage two" },
                "idempotency_key" => "intent-accepted-2",
              },
            ],
          },
        ],
      }
    )

    yield_event = workflow_run.reload.workflow_node_events.find_by!(
      workflow_node: yielding_node,
      event_kind: "yield_requested"
    )

    assert_equal %w[ops-annotation-1 ops-annotation-2], result.accepted_nodes.map(&:node_key)
    assert_equal ["batch-3:stage:1"], result.barrier_artifacts.map(&:artifact_key)
    assert_equal 2, result.manifest_artifact.payload["accepted_intent_count"]
    assert_equal 1, result.manifest_artifact.payload["rejected_intent_count"]
    assert_equal ["intent-rejected-1"], yield_event.payload["rejected_intent_ids"]
    assert_equal ["batch-3:stage:1"], yield_event.payload["barrier_artifact_keys"]
  end
end
