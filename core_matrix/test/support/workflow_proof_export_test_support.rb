module WorkflowProofExportTestSupport
  def build_workflow_proof_fixture!
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Proof export input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {
        "normalized_selector" => "candidate:dev/mock-model",
        "selector_source" => "conversation",
        "resolved_provider_handle" => "dev",
        "resolved_model_ref" => "mock-model",
      }
    )
    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "agent_step_1",
      root_node_type: "turn_step",
      decision_source: "agent_program",
      metadata: {}
    )

    yielding_node = workflow_run.workflow_nodes.first
    durable_node = create_workflow_node!(
      workflow_run: workflow_run,
      ordinal: 1,
      node_key: "governed_tool",
      node_type: "conversation_title_update",
      intent_kind: "conversation_title_update",
      intent_batch_id: "batch-1",
      intent_id: "intent-1",
      intent_requirement: "required",
      intent_conflict_scope: "conversation_metadata",
      intent_idempotency_key: "intent-1",
      yielding_workflow_node: yielding_node,
      decision_source: "system",
      presentation_policy: "ops_trackable",
      blocked_retry_failure_kind: "provider_rate_limited",
      blocked_retry_attempt_no: 2,
      metadata: {}
    )
    successor_node = create_workflow_node!(
      workflow_run: workflow_run,
      ordinal: 2,
      node_key: "agent_step_2",
      node_type: "turn_step",
      decision_source: "agent_program",
      presentation_policy: "internal_only",
      provider_round_index: 2,
      prior_tool_node_keys: ["governed_tool"],
      transcript_side_effect_committed: true,
      metadata: {
        "resumed_from" => "agent_step_1",
      }
    )

    create_workflow_edge!(
      workflow_run: workflow_run,
      from_node: yielding_node,
      to_node: durable_node,
      ordinal: 0
    )
    create_workflow_edge!(
      workflow_run: workflow_run,
      from_node: durable_node,
      to_node: successor_node,
      ordinal: 0
    )

    WorkflowNodeEvent.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workflow_node: yielding_node,
      event_kind: "status",
      ordinal: 0,
      payload: { "state" => "running" }
    )
    WorkflowNodeEvent.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workflow_node: yielding_node,
      event_kind: "yield_requested",
      ordinal: 1,
      payload: {
        "batch_id" => "batch-1",
        "accepted_node_keys" => ["governed_tool"],
        "barrier_artifact_keys" => ["batch-1:stage:0"],
      }
    )
    WorkflowNodeEvent.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workflow_node: durable_node,
      event_kind: "status",
      ordinal: 0,
      payload: { "state" => "completed" }
    )
    WorkflowNodeEvent.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workflow_node: successor_node,
      event_kind: "status",
      ordinal: 0,
      payload: { "state" => "queued" }
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
        "accepted_intent_count" => 1,
        "rejected_intent_count" => 0,
        "stages" => [
          {
            "stage_index" => 0,
            "dispatch_mode" => "serial",
            "completion_barrier" => "wait_all",
            "intents" => [
              {
                "intent_id" => "intent-1",
                "intent_kind" => "conversation_title_update",
                "node_key" => durable_node.node_key,
                "payload" => { "title" => "Retitled" },
              },
            ],
          },
        ],
      }
    )

    WorkflowArtifact.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workflow_node: yielding_node,
      artifact_key: "batch-1:stage:0",
      artifact_kind: "intent_batch_barrier",
      storage_mode: "json_document",
      payload: {
        "stage" => {
          "stage_index" => 0,
          "dispatch_mode" => "serial",
          "completion_barrier" => "wait_all",
        },
      }
    )

    workflow_run.update!(
      resume_policy: "re_enter_agent",
      resume_batch_id: "batch-1",
      resume_yielding_node_key: yielding_node.node_key,
      resume_successor_node_key: "agent_step_2",
      resume_successor_node_type: "turn_step"
    )

    {
      conversation: conversation,
      turn: turn.reload,
      workflow_run: workflow_run.reload,
      yielding_node: yielding_node.reload,
      durable_node: durable_node.reload,
      successor_node: successor_node.reload,
      expected_dag_shape: [
        "agent_step_1->governed_tool",
        "governed_tool->agent_step_2",
      ],
      expected_conversation_state: {
        "conversation_state" => "active",
        "workflow_lifecycle_state" => "active",
        "workflow_wait_state" => "ready",
        "turn_lifecycle_state" => "active",
      },
    }.merge(context)
  end
end

ActiveSupport::TestCase.include(WorkflowProofExportTestSupport)
