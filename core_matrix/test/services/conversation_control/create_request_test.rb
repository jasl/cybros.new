require "test_helper"

class ConversationControl::CreateRequestTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "request_status_refresh creates an auditable control request and a mailbox request" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    assert_difference("ConversationControlRequest.count", 1) do
      assert_difference("AgentControlMailboxItem.where(item_type: 'agent_request').count", 1) do
        request = ConversationControl::CreateRequest.call(
          actor: fixture.fetch(:user),
          conversation_supervision_session: session,
          request_kind: "request_status_refresh",
          request_payload: {}
        )

        mailbox_item = AgentControlMailboxItem.order(:id).last

        assert_equal "dispatched", request.lifecycle_state
        assert_equal "conversation", request.target_kind
        assert_equal fixture.fetch(:conversation).public_id, request.target_public_id
        assert_equal "supervision_status_refresh", mailbox_item.payload.fetch("request_kind")
        assert_equal request.public_id, mailbox_item.payload.dig("conversation_control", "conversation_control_request_id")
      end
    end
  end

  test "send_guidance_to_subagent creates a durable request without mutating the target transcript at create time" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    assert_difference("ConversationControlRequest.count", 1) do
      assert_no_difference(-> { fixture.fetch(:subagent_connection).conversation.messages.count }) do
        request = ConversationControl::CreateRequest.call(
          actor: fixture.fetch(:user),
          conversation_supervision_session: session,
          request_kind: "send_guidance_to_subagent",
          request_payload: {
            "subagent_connection_id" => fixture.fetch(:subagent_connection).public_id,
            "content" => "Please stop and summarize your current status.",
          }
        )

        assert_equal "dispatched", request.lifecycle_state
        assert_equal "subagent_connection", request.target_kind
        assert_equal fixture.fetch(:subagent_connection).public_id, request.target_public_id
      end
    end
  end

  test "disabled control capability blocks request creation before dispatch begins" do
    fixture = prepare_conversation_supervision_context!(control_enabled: false)
    session = create_conversation_supervision_session!(fixture)

    assert_no_difference("ConversationControlRequest.count") do
      assert_no_difference("AgentControlMailboxItem.count") do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          ConversationControl::CreateRequest.call(
            actor: fixture.fetch(:user),
            conversation_supervision_session: session,
            request_kind: "request_status_refresh",
            request_payload: {}
          )
        end

        assert_includes error.record.errors[:base], "control is not enabled for this conversation"
      end
    end
  end

  test "request_status_refresh targets the active runtime agent definition after a runtime rotation" do
    context = build_rotated_runtime_context!
    ConversationCapabilityPolicy.create!(
      installation: context.fetch(:installation),
      target_conversation: context.fetch(:conversation),
      supervision_enabled: true,
      side_chat_enabled: true,
      control_enabled: true,
      policy_payload: {}
    )
    session = ConversationSupervisionSession.create!(
      installation: context.fetch(:installation),
      target_conversation: context.fetch(:conversation),
      initiator: context.fetch(:user),
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {
        "supervision_enabled" => true,
        "side_chat_enabled" => true,
        "control_enabled" => true,
      },
      last_snapshot_at: Time.current
    )

    request = ConversationControl::CreateRequest.call(
      actor: context.fetch(:user),
      conversation_supervision_session: session,
      request_kind: "request_status_refresh",
      request_payload: {}
    )
    mailbox_item = AgentControlMailboxItem.order(:id).last

    assert_equal "dispatched", request.lifecycle_state
    assert_equal context.fetch(:replacement_agent_definition_version), mailbox_item.target_agent_definition_version
  end

  test "resume_waiting_workflow uses the authorized requester as the recovery audit actor" do
    context = build_agent_control_context!
    outsider = create_user!(installation: context.fetch(:installation))
    ConversationCapabilityPolicy.create!(
      installation: context.fetch(:installation),
      target_conversation: context.fetch(:conversation),
      supervision_enabled: true,
      side_chat_enabled: true,
      control_enabled: true,
      policy_payload: {}
    )
    ConversationCapabilityGrant.create!(
      installation: context.fetch(:installation),
      target_conversation: context.fetch(:conversation),
      grantee_kind: "user",
      grantee_public_id: outsider.public_id,
      capability: "resume_waiting_workflow",
      grant_state: "active",
      policy_payload: {}
    )
    context.fetch(:workflow_run).update!(
      wait_state: "waiting",
      wait_reason_kind: "manual_recovery_required",
      wait_reason_payload: {},
      waiting_since_at: Time.current,
      recovery_state: "paused_agent_unavailable"
    )
    session = ConversationSupervisionSession.create!(
      installation: context.fetch(:installation),
      target_conversation: context.fetch(:conversation),
      initiator: context.fetch(:user),
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {
        "supervision_enabled" => true,
        "side_chat_enabled" => true,
        "control_enabled" => true,
      },
      last_snapshot_at: Time.current
    )
    captured = nil
    original_call = Workflows::ManualResume.method(:call)
    Workflows::ManualResume.singleton_class.define_method(:call) do |workflow_run:, agent_definition_version:, actor:, conversation_control_request: nil, **_rest|
      captured = [workflow_run.public_id, agent_definition_version.public_id, actor.public_id, conversation_control_request&.public_id]
      workflow_run
    end

    begin
      ConversationControl::CreateRequest.call(
        actor: outsider,
        conversation_supervision_session: session,
        request_kind: "resume_waiting_workflow",
        request_payload: {}
      )
    ensure
      Workflows::ManualResume.singleton_class.define_method(:call, original_call)
    end

    request = ConversationControlRequest.order(:id).last

    assert_equal [
      context.fetch(:workflow_run).public_id,
      context.fetch(:agent_definition_version).public_id,
      outsider.public_id,
      request.public_id,
    ], captured
  end
end
