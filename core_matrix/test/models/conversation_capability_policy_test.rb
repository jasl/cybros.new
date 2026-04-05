require "test_helper"

class ConversationCapabilityPolicyTest < ActiveSupport::TestCase
  test "generates a public id and gates supervision side chat and control per conversation" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )

    policy = ConversationCapabilityPolicy.create!(
      installation: context[:installation],
      target_conversation: conversation,
      supervision_enabled: true,
      detailed_progress_enabled: true,
      side_chat_enabled: true,
      control_enabled: false,
      policy_payload: { "default_surface" => "side_chat" }
    )

    assert policy.public_id.present?
    assert_equal policy, ConversationCapabilityPolicy.find_by_public_id!(policy.public_id)
    assert_equal conversation, policy.target_conversation
    assert_predicate policy, :supervision_enabled?
    assert_predicate policy, :detailed_progress_enabled?
    assert_predicate policy, :side_chat_enabled?
    assert_not policy.control_enabled?
    assert_equal 1, conversation.conversation_capability_policy ? 1 : 0
    assert_not_nil Conversation.reflect_on_association(:conversation_capability_policy)
  end

  test "requires a single policy per conversation and a matching installation" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )
    ConversationCapabilityPolicy.create!(
      installation: context[:installation],
      target_conversation: conversation,
      supervision_enabled: true,
      detailed_progress_enabled: true,
      side_chat_enabled: true,
      control_enabled: true,
      policy_payload: {}
    )

    duplicate = ConversationCapabilityPolicy.new(
      installation: context[:installation],
      target_conversation: conversation,
      supervision_enabled: false,
      detailed_progress_enabled: false,
      side_chat_enabled: false,
      control_enabled: false,
      policy_payload: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:target_conversation], "has already been taken"

    other_installation = create_raw_installation!
    mismatched = ConversationCapabilityPolicy.new(
      installation: other_installation,
      target_conversation: conversation,
      supervision_enabled: true,
      detailed_progress_enabled: true,
      side_chat_enabled: true,
      control_enabled: false,
      policy_payload: {}
    )

    assert_not mismatched.valid?
    assert_includes mismatched.errors[:target_conversation], "must belong to the same installation"
  end

  private

  def create_raw_installation!
    now = Time.current
    sql = <<~SQL.squish
      INSERT INTO installations (name, bootstrap_state, global_settings, created_at, updated_at)
      VALUES (#{ApplicationRecord.connection.quote("Supervision Policy Installation #{next_test_sequence}")},
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
