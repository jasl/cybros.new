require "test_helper"

class Conversations::ValidateQuiescenceTest < ActiveSupport::TestCase
  test "legacy work quiescence guard module is removed" do
    refute Conversations.constants.include?(legacy_guard_constant_name)
  end

  test "archival rejects open owned subagent sessions" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    session = create_owned_subagent_session!(
      installation: context[:installation],
      workspace: context[:workspace],
      owner_conversation: conversation,
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateQuiescence.call(
        conversation: conversation,
        stage: "archival",
        mainline_only: false
      )
    end

    assert_equal conversation.id, error.record.id
    assert_includes error.record.errors[:base], "must not have open subagent sessions before archival"
    assert session.reload.close_open?
  end

  test "purge rejects close-pending owned subagent sessions" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    session = create_owned_subagent_session!(
      installation: context[:installation],
      workspace: context[:workspace],
      owner_conversation: conversation,
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    session.update!(
      close_state: "requested",
      close_reason_kind: "conversation_deleted",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateQuiescence.call(
        conversation: conversation,
        stage: "purge",
        mainline_only: false
      )
    end

    assert_equal conversation.id, error.record.id
    assert_includes error.record.errors[:base], "must not have open or close-pending subagent sessions before purge"
    assert_equal "close_requested", session.reload.derived_close_status
  end

  test "final deletion ignores disposing background-service tails once the mainline barrier is clear" do
    context = build_agent_control_context!
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)
    context[:turn].update!(
      lifecycle_state: "canceled",
      cancellation_requested_at: Time.current,
      cancellation_reason_kind: "turn_interrupted"
    )
    context[:workflow_run].update!(
      lifecycle_state: "canceled",
      wait_state: "ready",
      wait_reason_kind: nil,
      wait_reason_payload: {},
      waiting_since_at: nil,
      blocking_resource_type: nil,
      blocking_resource_id: nil,
      cancellation_requested_at: Time.current,
      cancellation_reason_kind: "turn_interrupted"
    )
    background_service = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil
    )
    background_service.update!(
      close_state: "requested",
      close_reason_kind: "conversation_deleted",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now
    )

    validated = Conversations::ValidateQuiescence.call(
      conversation: context[:conversation],
      stage: "final deletion",
      mainline_only: true
    )

    assert_equal context[:conversation].id, validated.id
  end

  private

  def legacy_guard_constant_name
    %i[Work Quiescence Guard].join.to_sym
  end

  def create_owned_subagent_session!(installation:, workspace:, owner_conversation:, execution_environment:, agent_deployment:)
    child_conversation = create_conversation_record!(
      installation: installation,
      workspace: workspace,
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_environment: execution_environment,
      agent_deployment: agent_deployment,
      addressability: "agent_addressable"
    )
    SubagentSession.create!(
      installation: installation,
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "idle"
    )
  end
end
