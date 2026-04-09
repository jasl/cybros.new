require "test_helper"

class EmbeddedAgents::ConversationSupervision::CloseSessionTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "closes an authorized supervision session and stamps closed_at" do
    fixture = prepare_conversation_supervision_context!
    session = create_conversation_supervision_session!(fixture)

    travel_to(Time.utc(2026, 4, 9, 16, 0, 0)) do
      result = EmbeddedAgents::ConversationSupervision::CloseSession.call(
        actor: fixture.fetch(:user),
        conversation_supervision_session: session
      )

      assert_equal session, result
      assert_equal "closed", result.lifecycle_state
      assert_equal Time.utc(2026, 4, 9, 16, 0, 0), result.closed_at
    end
  end

  test "is idempotent for an already closed session" do
    fixture = prepare_conversation_supervision_context!
    session = create_conversation_supervision_session!(fixture)
    travel_to(Time.utc(2026, 4, 9, 16, 0, 0)) { session.update!(lifecycle_state: "closed") }

    travel_to(Time.utc(2026, 4, 9, 17, 0, 0)) do
      result = EmbeddedAgents::ConversationSupervision::CloseSession.call(
        actor: fixture.fetch(:user),
        conversation_supervision_session: session
      )

      assert_equal Time.utc(2026, 4, 9, 16, 0, 0), result.closed_at
    end
  end

  test "rejects unauthorized actors" do
    fixture = prepare_conversation_supervision_context!
    session = create_conversation_supervision_session!(fixture)
    outsider = create_user!(installation: fixture.fetch(:installation))

    error = assert_raises(EmbeddedAgents::Errors::UnauthorizedSupervision) do
      EmbeddedAgents::ConversationSupervision::CloseSession.call(
        actor: outsider,
        conversation_supervision_session: session
      )
    end

    assert_equal "not allowed to supervise conversation", error.message
    assert_equal "open", session.reload.lifecycle_state
  end
end
