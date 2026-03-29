require "test_helper"

class Workflows::ProjectionTest < ActiveSupport::TestCase
  test "reads yielded workflow state through projection metadata without graph reconstruction queries" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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
              {
                "intent_id" => "intent-2",
                "intent_kind" => "subagent_spawn",
                "node_key" => "subagent-1",
                "node_type" => "subagent_spawn",
                "requirement" => "best_effort",
                "conflict_scope" => "subagent_pool",
                "presentation_policy" => "ops_trackable",
                "durable_outcome" => "rejected",
                "rejection_reason" => "parallel_conflict",
                "payload" => { "agent" => "fenix-helper" },
                "idempotency_key" => "intent-2",
              },
            ],
          },
        ],
      }
    )

    projection = nil
    queries = capture_sql_queries do
      projection = workflow_projection_class.call(workflow_run: workflow_run)
    end

    assert_operator queries.size, :<=, 5
    assert_equal %w[agent_step_1 title-update], projection.nodes.map(&:node_key)
    assert_equal %w[intent_batch_barrier intent_batch_manifest], projection.artifacts_by_node_key.fetch("agent_step_1").map(&:artifact_kind).sort
    assert_equal %w[intent_rejected yield_requested], projection.events_by_node_key.fetch("agent_step_1").map(&:event_kind).sort
    assert_equal "re_enter_agent", projection.workflow_run.resume_policy
    assert_equal "agent_step_2", projection.workflow_run.resume_metadata.dig("successor", "node_key")
  end

  private

  def workflow_projection_class
    @workflow_projection_class ||= Workflows.const_get(:Projection, false)
  rescue NameError
    flunk "Workflows::Projection must exist"
  end
end
