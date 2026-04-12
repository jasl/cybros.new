require "test_helper"

class AppSurface::Policies::ConversationSupervisionAccessTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "allows the workspace owner to create supervision when side chat is enabled" do
    fixture = prepare_conversation_supervision_context!

    access = AppSurface::Policies::ConversationSupervisionAccess.call(
      user: fixture.fetch(:user),
      conversation: fixture.fetch(:conversation)
    )

    assert_predicate access, :read?
    assert_predicate access, :create_session?
    assert_predicate access, :side_chat_enabled?
    assert_equal [], access.available_control_verbs
  end

  test "denies access when the conversation becomes inaccessible" do
    fixture = prepare_conversation_supervision_context!
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

    access = AppSurface::Policies::ConversationSupervisionAccess.call(
      user: fixture.fetch(:user),
      conversation: fixture.fetch(:conversation)
    )

    assert_not access.read?
    assert_not access.create_session?
    assert_not access.append_message?
    assert_not access.close_session?
  end

  test "denies create and close when side chat is disabled" do
    fixture = prepare_conversation_supervision_context!(side_chat_enabled: false)
    session = create_conversation_supervision_session!(fixture)

    access = AppSurface::Policies::ConversationSupervisionAccess.call(
      user: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    assert_predicate access, :read?
    assert_not access.create_session?
    assert_not access.append_message?
    assert_not access.close_session?
  end

  test "requires the session initiator to append messages" do
    fixture = prepare_conversation_supervision_context!
    outsider = create_user!(
      installation: fixture.fetch(:installation),
      identity: create_identity!,
      display_name: "Other User"
    )
    session = create_conversation_supervision_session!(fixture, initiator: outsider)

    access = AppSurface::Policies::ConversationSupervisionAccess.call(
      user: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    assert_predicate access, :read?
    assert_not access.append_message?
    assert_predicate access, :close_session?
  end
end
