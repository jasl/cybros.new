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

  test "accessible_to_user keeps owner conversations while hiding deleted and hidden-agent rows" do
    context = conversation_context
    visible_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    deleted_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    deleted_conversation.update!(
      deletion_state: "deleted",
      deleted_at: Time.current
    )

    hidden_owner = create_user!(
      installation: context[:installation],
      identity: create_identity!,
      display_name: "Hidden Owner"
    )
    hidden_agent = create_agent!(
      installation: context[:installation],
      key: "hidden-agent"
    )
    hidden_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:workspace].user,
      agent: hidden_agent,
      name: "Hidden Agent Workspace"
    )
    Conversations::CreateRoot.call(
      workspace: hidden_workspace,
      agent: hidden_agent
    )
    hidden_agent.update!(
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: hidden_owner
    )

    assert_equal [visible_conversation], Conversation.accessible_to_user(context[:workspace].user).order(:id).to_a
  end

  test "stores override payloads in a detail row instead of the header table" do
    conversation = build_conversation(
      override_payload: { "subagents" => { "enabled" => false } },
      override_reconciliation_report: { "status" => "exact" }
    )

    conversation.save!

    refute_includes Conversation.column_names, "override_payload"
    refute_includes Conversation.column_names, "override_reconciliation_report"
    assert_equal :has_one, Conversation.reflect_on_association(:conversation_detail)&.macro
    assert_equal({ "subagents" => { "enabled" => false } }, conversation.override_payload)
    assert_equal({ "status" => "exact" }, conversation.override_reconciliation_report)
    assert_equal({ "status" => "exact" }, conversation.conversation_detail.override_reconciliation_report)
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
      workspace = create_workspace!(
        installation: installation,
        user: user,
        agent: agent
      )

      {
        installation: installation,
        workspace: workspace,
        agent: agent,
      }
    end
  end
end
