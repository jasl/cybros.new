require "test_helper"

class ConversationCapabilityGrantTest < ActiveSupport::TestCase
  test "defines who may read or control a conversation using public ids only" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      executor_program: context[:executor_program],
      agent_program: context[:agent_program]
    )

    grant = ConversationCapabilityGrant.create!(
      installation: context[:installation],
      target_conversation: conversation,
      grantee_kind: "user",
      grantee_public_id: context[:user].public_id,
      capability: "request_turn_interrupt",
      grant_state: "active",
      policy_payload: { "scope" => "side_chat" },
      expires_at: 1.hour.from_now
    )

    assert grant.public_id.present?
    assert_equal grant, ConversationCapabilityGrant.find_by_public_id!(grant.public_id)
    assert_equal context[:user].public_id, grant.grantee_public_id
    assert_equal "request_turn_interrupt", grant.capability
    assert_equal grant, conversation.conversation_capability_grants.last
  end

  test "requires installation to match the target conversation" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      executor_program: context[:executor_program],
      agent_program: context[:agent_program]
    )
    other_installation = create_raw_installation!

    grant = ConversationCapabilityGrant.new(
      installation: other_installation,
      target_conversation: conversation,
      grantee_kind: "user",
      grantee_public_id: context[:user].public_id,
      capability: "read_supervision",
      grant_state: "active",
      policy_payload: {}
    )

    assert_not grant.valid?
    assert_includes grant.errors[:target_conversation], "must belong to the same installation"
  end

  private

  def create_raw_installation!
    now = Time.current
    sql = <<~SQL.squish
      INSERT INTO installations (name, bootstrap_state, global_settings, created_at, updated_at)
      VALUES (#{ApplicationRecord.connection.quote("Capability Grant Installation #{next_test_sequence}")},
              'bootstrapped',
              '{}',
              #{ApplicationRecord.connection.quote(now)},
              #{ApplicationRecord.connection.quote(now)})
      RETURNING id
    SQL
    installation_id = ApplicationRecord.connection.select_value(sql)
    Installation.find(installation_id)
  end
end
