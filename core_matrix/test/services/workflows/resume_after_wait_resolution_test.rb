require "test_helper"

class Workflows::ResumeAfterWaitResolutionTest < ActiveSupport::TestCase
  test "re-enters a subagent barrier using barrier artifact-backed spawn nodes" do
    context = build_subagent_barrier_waiting_context!
    context[:subagent_connections].each { |session| session.update!(observed_status: "completed") }

    re_enter_call = nil
    original_re_enter = Workflows::ReEnterAgent.method(:call)
    Workflows::ReEnterAgent.singleton_class.define_method(:call) do |*args, **kwargs|
      re_enter_call = kwargs
      original_re_enter.call(*args, **kwargs)
    end

    Workflows::ResumeAfterWaitResolution.call(workflow_run: context[:workflow_run])

    assert re_enter_call
    assert_equal "wait_resolved", re_enter_call.fetch(:resume_reason)
    assert_equal({}, re_enter_call.fetch(:wait_context).fetch("wait_reason_payload"))
    assert_equal context[:spawn_nodes].map(&:id).sort,
      re_enter_call.fetch(:predecessor_nodes).map(&:id).sort

    workflow_run = context[:workflow_run].reload
    assert workflow_run.ready?
    assert_nil workflow_run.wait_reason_kind
    assert_equal({}, workflow_run.wait_reason_payload)
  ensure
    if original_re_enter
      Workflows::ReEnterAgent.singleton_class.define_method(:call, original_re_enter)
    end
  end

  private

  def build_subagent_barrier_waiting_context!
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Delegate work",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    yielding_node = create_workflow_node!(
      workflow_run: workflow_run,
      ordinal: 0,
      node_key: "agent_step_1",
      node_type: "agent_task_run",
      lifecycle_state: "completed",
      started_at: 3.minutes.ago,
      finished_at: 2.minutes.ago
    )

    subagent_connections = 2.times.map do |index|
      child_conversation = create_conversation_record!(
        workspace: context[:workspace],
        installation: context[:installation],
        parent_conversation: conversation,
        kind: "fork",
        addressability: "agent_addressable",
        execution_runtime: context[:execution_runtime],
        agent_definition_version: context[:agent_definition_version]
      )

      SubagentConnection.create!(
        installation: context[:installation],
        owner_conversation: conversation,
        conversation: child_conversation,
        origin_turn: turn,
        scope: "conversation",
        profile_key: "researcher",
        depth: 0,
        observed_status: index.zero? ? "running" : "waiting"
      )
    end

    spawn_nodes = subagent_connections.map.with_index(1) do |session, index|
      create_workflow_node!(
        workflow_run: workflow_run,
        ordinal: index,
        node_key: "subagent_#{index}",
        node_type: "subagent_spawn",
        lifecycle_state: "completed",
        intent_kind: "subagent_spawn",
        intent_batch_id: "batch-subagents-1",
        intent_id: "intent-subagent-#{index}",
        intent_requirement: "required",
        stage_index: 0,
        stage_position: index - 1,
        yielding_workflow_node: yielding_node,
        spawned_subagent_connection: session,
        started_at: 90.seconds.ago,
        finished_at: 80.seconds.ago
      )
    end

    WorkflowArtifact.create!(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: yielding_node,
      artifact_key: "batch-subagents-1:stage:0",
      artifact_kind: "intent_batch_barrier",
      storage_mode: "json_document",
      payload: {
        "batch_id" => "batch-subagents-1",
        "stage" => {
          "stage_index" => 0,
          "dispatch_mode" => "parallel",
          "completion_barrier" => "wait_all",
        },
        "accepted_intent_ids" => spawn_nodes.map(&:intent_id),
        "rejected_intent_ids" => [],
      }
    )

    workflow_run.update!(
      wait_state: "waiting",
      wait_reason_kind: "subagent_barrier",
      wait_reason_payload: {},
      waiting_since_at: Time.current,
      blocking_resource_type: "SubagentBarrier",
      blocking_resource_id: "batch-subagents-1:stage:0"
    )

    {
      workflow_run: workflow_run,
      subagent_connections: subagent_connections,
      spawn_nodes: spawn_nodes,
    }
  end
end
