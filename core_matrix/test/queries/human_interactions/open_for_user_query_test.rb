require "test_helper"

class HumanInteractions::OpenForUserQueryTest < ActiveSupport::TestCase
  test "returns only open requests owned by the users private workspaces including automation conversations" do
    installation = create_installation!
    user = create_user!(installation: installation, display_name: "Inbox Owner")
    other_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Other User"
    )

    shared_context = build_request_context(installation: installation, user: user)
    interactive_request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: shared_context[:interactive][:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Review the interactive task" }
    )
    automation_request = HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: shared_context[:automation][:workflow_node],
      blocking: true,
      request_payload: { "approval_scope" => "publish" }
    )
    resolved_request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: build_request_context(installation: installation, user: user)[:interactive][:workflow_node],
      blocking: false,
      request_payload: { "instructions" => "Already handled" }
    )
    resolved_request.resolve!(
      resolution_kind: "completed",
      result_payload: { "status" => "done" }
    )
    other_users_request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: build_request_context(installation: installation, user: other_user)[:interactive][:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Other users task" }
    )

    result = HumanInteractions::OpenForUserQuery.call(user: user)

    assert_equal [interactive_request, automation_request], result
    assert_not_includes result, resolved_request
    assert_not_includes result, other_users_request
  end

  test "excludes archived conversations even if an open request still exists" do
    installation = create_installation!
    user = create_user!(installation: installation, display_name: "Inbox Owner")
    context = build_request_context(installation: installation, user: user)
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:interactive][:workflow_node],
      blocking: false,
      request_payload: { "instructions" => "Optional archived follow-up" }
    )
    context[:interactive][:conversation].update!(lifecycle_state: "archived")

    result = HumanInteractions::OpenForUserQuery.call(user: user)

    assert_not_includes result, request
  end

  private

  def build_request_context(installation:, user:)
    agent = create_agent!(installation: installation, key: "agent-#{next_test_sequence}")
    execution_runtime = create_execution_runtime!(installation: installation)
    agent_snapshot = create_agent_snapshot!(
      installation: installation,
      agent: agent
    )
    create_agent_connection!(
      installation: installation,
      agent: agent,
      agent_snapshot: agent_snapshot,
      health_status: "healthy",
      auto_resume_eligible: true,
      last_heartbeat_at: Time.current,
      last_health_check_at: Time.current
    )
    create_execution_runtime_connection!(
      installation: installation,
      execution_runtime: execution_runtime,
      last_heartbeat_at: Time.current
    )
    user_agent_binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent: agent
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: user_agent_binding
    )

    interactive_conversation = Conversations::CreateRoot.call(
      workspace: workspace,
      agent: agent
    )
    interactive_turn = Turns::StartUserTurn.call(
      conversation: interactive_conversation,
      content: "Interactive task",
      execution_runtime: execution_runtime,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    interactive_workflow_run = create_workflow_run!(turn: interactive_turn)
    create_workflow_node!(
      workflow_run: interactive_workflow_run,
      ordinal: 0,
      node_key: "human_gate",
      node_type: "human_interaction",
      decision_source: "agent",
      metadata: {}
    )

    automation_conversation = Conversations::CreateAutomationRoot.call(
      workspace: workspace,
      agent: agent
    )
    automation_conversation.update!(
      enabled_feature_ids: (automation_conversation.enabled_feature_ids + ["human_interaction"]).uniq
    )
    automation_turn = Turns::StartAutomationTurn.call(
      conversation: automation_conversation,
      origin_kind: "automation_schedule",
      origin_payload: { "cron" => "0 9 * * *" },
      source_ref_type: "AutomationSchedule",
      source_ref_id: "schedule-#{next_test_sequence}",
      idempotency_key: "idempotency-#{next_test_sequence}",
      external_event_key: "event-#{next_test_sequence}",
      execution_runtime: execution_runtime,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    automation_workflow_run = create_workflow_run!(turn: automation_turn)
    create_workflow_node!(
      workflow_run: automation_workflow_run,
      ordinal: 0,
      node_key: "human_gate",
      node_type: "human_interaction",
      decision_source: "agent",
      metadata: {}
    )

    {
      installation: installation,
      user: user,
      agent: agent,
      execution_runtime: execution_runtime,
      agent_snapshot: agent_snapshot,
      user_agent_binding: user_agent_binding,
      workspace: workspace,
      interactive: {
        conversation: interactive_conversation,
        turn: interactive_turn,
        workflow_run: interactive_workflow_run,
        workflow_node: interactive_workflow_run.workflow_nodes.find_by!(node_key: "human_gate"),
      },
      automation: {
        conversation: automation_conversation,
        turn: automation_turn,
        workflow_run: automation_workflow_run,
        workflow_node: automation_workflow_run.workflow_nodes.find_by!(node_key: "human_gate"),
      },
    }
  end
end
