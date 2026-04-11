require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  VALID_METADATA_SOURCES = %w[none bootstrap generated agent user].freeze
  VALID_LOCK_STATES = %w[unlocked user_locked].freeze

  test "generates and resolves a public id" do
    conversation = build_conversation
    conversation.save!

    assert conversation.public_id.present?
    assert_equal conversation, Conversation.find_by_public_id!(conversation.public_id)
  end

  test "binds to an agent and not directly to runtime rows" do
    conversation = build_conversation

    assert conversation.valid?
    assert_equal :belongs_to, Conversation.reflect_on_association(:workspace).macro
    assert_equal :belongs_to, Conversation.reflect_on_association(:agent).macro
    assert_nil Conversation.reflect_on_association(:agent_snapshot)
    assert_nil Conversation.reflect_on_association(:execution_runtime)
    assert_not_includes Conversation.column_names, "agent_snapshot_id"
    assert_not_includes Conversation.column_names, "execution_runtime_id"
  end

  test "exposes inline metadata fields on conversation" do
    metadata_fields = %w[
      title
      summary
      title_source
      summary_source
      title_lock_state
      summary_lock_state
      title_updated_at
      summary_updated_at
    ]

    metadata_fields.each do |field|
      assert_includes Conversation.column_names, field
    end
  end

  test "allows valid title and summary sources" do
    VALID_METADATA_SOURCES.each do |source|
      conversation = build_conversation(title_source: source, summary_source: source)
      assert conversation.valid?, "expected source #{source.inspect} to be valid: #{conversation.errors.full_messages.to_sentence}"
    end
  end

  test "allows valid title and summary lock states" do
    VALID_LOCK_STATES.each do |lock_state|
      conversation = build_conversation(title_lock_state: lock_state, summary_lock_state: lock_state)
      assert conversation.valid?, "expected lock state #{lock_state.inspect} to be valid: #{conversation.errors.full_messages.to_sentence}"
    end
  end

  test "title_locked? reflects title lock state" do
    unlocked_conversation = build_conversation(title_lock_state: "unlocked")
    user_locked_conversation = build_conversation(title_lock_state: "user_locked")

    assert_not unlocked_conversation.title_locked?
    assert user_locked_conversation.title_locked?
  end

  test "summary_locked? reflects summary lock state" do
    unlocked_conversation = build_conversation(summary_lock_state: "unlocked")
    user_locked_conversation = build_conversation(summary_lock_state: "user_locked")

    assert_not unlocked_conversation.summary_locked?
    assert user_locked_conversation.summary_locked?
  end

  test "rejects invalid title_source" do
    conversation = build_conversation(title_source: "invalid_source")

    assert_not conversation.valid?
    assert_includes conversation.errors[:title_source], "is not included in the list"
  end

  test "rejects invalid summary_source" do
    conversation = build_conversation(summary_source: "invalid_source")

    assert_not conversation.valid?
    assert_includes conversation.errors[:summary_source], "is not included in the list"
  end

  test "rejects invalid title_lock_state" do
    conversation = build_conversation(title_lock_state: "invalid_lock_state")

    assert_not conversation.valid?
    assert_includes conversation.errors[:title_lock_state], "is not included in the list"
  end

  test "rejects invalid summary_lock_state" do
    conversation = build_conversation(summary_lock_state: "invalid_lock_state")

    assert_not conversation.valid?
    assert_includes conversation.errors[:summary_lock_state], "is not included in the list"
  end

  test "defaults metadata sources and lock states on new and persisted conversation" do
    conversation = build_conversation

    assert_equal "none", conversation.title_source
    assert_equal "none", conversation.summary_source
    assert_equal "unlocked", conversation.title_lock_state
    assert_equal "unlocked", conversation.summary_lock_state

    conversation.save!
    conversation.reload

    assert_equal "none", conversation.title_source
    assert_equal "none", conversation.summary_source
    assert_equal "unlocked", conversation.title_lock_state
    assert_equal "unlocked", conversation.summary_lock_state
  end

  private

  def build_conversation(attributes = {})
    context = conversation_context

    Conversation.new(
      {
        installation: context[:installation],
        workspace: context[:workspace],
        agent: context[:agent],
        kind: "root",
        purpose: "interactive",
        lifecycle_state: "active",
      }.merge(attributes)
    )
  end

  def conversation_context
    @conversation_context ||= begin
      installation = create_installation!
      agent = create_agent!(installation: installation)
      user = create_user!(installation: installation)
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

      {
        installation: installation,
        workspace: workspace,
        agent: agent,
      }
    end
  end
end
