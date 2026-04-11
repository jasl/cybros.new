require "test_helper"

class EmbeddedAgents::ConversationSupervision::AuthorityTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "owner authority becomes inaccessible when the conversation agent turns private for another owner" do
    fixture = prepare_conversation_supervision_context!
    replacement_owner = create_user!(
      installation: fixture[:installation],
      identity: create_identity!,
      display_name: "Replacement Owner"
    )

    authority = EmbeddedAgents::ConversationSupervision::Authority.call(
      actor: fixture[:user],
      conversation: fixture[:conversation]
    )

    assert authority.accessible?
    assert authority.allowed?

    fixture[:agent].update!(
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: replacement_owner
    )

    authority = EmbeddedAgents::ConversationSupervision::Authority.call(
      actor: fixture[:user],
      conversation: fixture[:conversation]
    )

    assert_not authority.accessible?
    assert_not authority.allowed?
  end
end
