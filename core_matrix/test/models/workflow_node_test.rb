require "test_helper"

class WorkflowNodeTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run)

    assert workflow_node.public_id.present?
    assert workflow_node.pending?
    assert_equal workflow_node, WorkflowNode.find_by_public_id!(workflow_node.public_id)
  end

  test "tracks unique ordinals decision sources and audit metadata" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    node = create_workflow_node!(
      workflow_run: workflow_run,
      ordinal: 0,
      node_key: "root",
      node_type: "turn_root",
      decision_source: "system",
      metadata: { "policy_sensitive" => true }
    )
    duplicate_ordinal = WorkflowNode.new(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      ordinal: 0,
      node_key: "duplicate",
      node_type: "llm_call",
      decision_source: "llm",
      metadata: {}
    )

    assert node.system?
    assert_equal true, node.metadata["policy_sensitive"]
    assert_not duplicate_ordinal.valid?
    assert_includes duplicate_ordinal.errors[:ordinal], "has already been taken"
  end

  test "persists frozen presentation policy and yield linkage independently from node type" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    yielding_node = create_workflow_node!(
      workflow_run: workflow_run,
      ordinal: 0,
      node_key: "agent_step_1",
      node_type: "agent_task_run",
      presentation_policy: "ops_trackable"
    )

    annotation_node = WorkflowNode.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workspace: conversation.workspace,
      conversation: conversation,
      turn: turn,
      yielding_workflow_node: yielding_node,
      ordinal: 1,
      node_key: "ops-annotation",
      node_type: "ops_annotation",
      intent_kind: "ops_annotation",
      stage_index: 0,
      stage_position: 0,
      presentation_policy: "internal_only",
      decision_source: "agent",
      metadata: {}
    )
    operator_node = WorkflowNode.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workspace: conversation.workspace,
      conversation: conversation,
      turn: turn,
      yielding_workflow_node: yielding_node,
      ordinal: 2,
      node_key: "ops-annotation-ops",
      node_type: "ops_annotation",
      intent_kind: "ops_annotation",
      stage_index: 0,
      stage_position: 1,
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      metadata: {}
    )

    assert annotation_node.internal_only?
    assert operator_node.ops_trackable?
    assert_equal yielding_node, annotation_node.yielding_workflow_node
    assert_equal conversation.workspace, annotation_node.workspace
    assert_equal conversation, annotation_node.conversation
    assert_equal turn, annotation_node.turn
  end

  test "allows a waiting node to retain started_at without requiring finished_at" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = WorkflowNode.new(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workspace: conversation.workspace,
      conversation: conversation,
      turn: turn,
      ordinal: 0,
      node_key: "waiting-node",
      node_type: "turn_step",
      lifecycle_state: "waiting",
      presentation_policy: "internal_only",
      decision_source: "system",
      started_at: Time.current,
      finished_at: nil,
      metadata: {}
    )

    assert workflow_node.valid?
    refute workflow_node.terminal?
  end

  test "resolves intent payloads through the yielding batch manifest instead of inline metadata" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    yielding_node = create_workflow_node!(
      workflow_run: workflow_run,
      ordinal: 0,
      node_key: "agent_step_1",
      node_type: "agent_task_run"
    )

    WorkflowArtifact.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workflow_node: yielding_node,
      artifact_key: "batch-1",
      artifact_kind: "intent_batch_manifest",
      storage_mode: "json_document",
      payload: {
        "batch_id" => "batch-1",
        "stages" => [
          {
            "stage_index" => 0,
            "dispatch_mode" => "serial",
            "completion_barrier" => "none",
            "intents" => [
              {
                "intent_id" => "intent-1",
                "intent_kind" => "ops_annotation",
                "payload" => { "note" => "Retitled" },
              },
            ],
          },
        ],
      }
    )

    node = WorkflowNode.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workspace: conversation.workspace,
      conversation: conversation,
      turn: turn,
      yielding_workflow_node: yielding_node,
      ordinal: 1,
      node_key: "ops-annotation",
      node_type: "ops_annotation",
      intent_kind: "ops_annotation",
      intent_batch_id: "batch-1",
      intent_id: "intent-1",
      presentation_policy: "internal_only",
      decision_source: "agent",
      metadata: {}
    )

    assert_equal({ "note" => "Retitled" }, node.intent_payload)
  end
end
