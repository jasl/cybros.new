require "test_helper"

class ConversationControl::AuthorizeRequestTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "authorizes the owner when control is enabled" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    result = ConversationControl::AuthorizeRequest.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      request_kind: "request_turn_interrupt",
      request_payload: {}
    )

    assert result.allowed?
    assert_equal "conversation", result.target_kind
    assert_equal fixture.fetch(:conversation).public_id, result.target_public_id
    refute_respond_to result, :policy
  end

  test "rejects the original owner after a visibility change when no explicit capability grant exists" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)
    replacement_owner = create_user!(
      installation: fixture.fetch(:installation),
      identity: create_identity!,
      display_name: "Replacement Owner"
    )
    fixture.fetch(:agent).update!(
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: replacement_owner
    )

    denied = ConversationControl::AuthorizeRequest.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      request_kind: "request_turn_interrupt",
      request_payload: {}
    )

    assert_not denied.allowed?
    assert_equal "actor is not allowed to control this conversation", denied.rejection_reason
  end

  test "allows an explicit capability grant for a non-owner caller" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)
    outsider = create_user!(installation: fixture.fetch(:installation))

    denied = ConversationControl::AuthorizeRequest.call(
      actor: outsider,
      conversation_supervision_session: session,
      request_kind: "request_turn_interrupt",
      request_payload: {}
    )

    assert_not denied.allowed?
    assert_equal "actor is not allowed to control this conversation", denied.rejection_reason

    ConversationCapabilityGrant.create!(
      installation: fixture.fetch(:installation),
      target_conversation: fixture.fetch(:conversation),
      grantee_kind: "user",
      grantee_public_id: outsider.public_id,
      capability: "request_turn_interrupt",
      grant_state: "active",
      policy_payload: {}
    )

    allowed = ConversationControl::AuthorizeRequest.call(
      actor: outsider,
      conversation_supervision_session: session,
      request_kind: "request_turn_interrupt",
      request_payload: {}
    )

    assert allowed.allowed?
  end

  test "resume_waiting_workflow is rejected unless the current workflow wait reason allows it" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true, waiting: false)
    session = create_conversation_supervision_session!(fixture)

    result = ConversationControl::AuthorizeRequest.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      request_kind: "resume_waiting_workflow",
      request_payload: {}
    )

    assert result.allowed?
    assert_equal "workflow_run", result.target_kind
    assert_equal fixture.fetch(:workflow_run).public_id, result.target_public_id
  end

  test "retry_blocked_step resolves the active workflow target for later dispatch validation" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    result = ConversationControl::AuthorizeRequest.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      request_kind: "retry_blocked_step",
      request_payload: {}
    )

    assert result.allowed?
    assert_equal "workflow_run", result.target_kind
    assert_equal fixture.fetch(:workflow_run).public_id, result.target_public_id
  end
end
