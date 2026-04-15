require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  VALID_METADATA_SOURCES = %w[none bootstrap generated agent user].freeze
  VALID_LABEL_LOCK_STATES = %w[unlocked user_locked].freeze
  VALID_INTERACTION_LOCK_STATES = %w[mutable locked_agent_access_revoked archived deleted].freeze

  test "generates and resolves a public id" do
    conversation = build_conversation
    conversation.save!

    assert conversation.public_id.present?
    assert_equal conversation, Conversation.find_by_public_id!(conversation.public_id)
  end

  test "binds to a workspace agent and not directly to runtime rows" do
    conversation = build_conversation

    assert conversation.valid?, conversation.errors.full_messages.to_sentence
    assert_equal :belongs_to, Conversation.reflect_on_association(:workspace_agent)&.macro
    assert_equal :belongs_to, Conversation.reflect_on_association(:workspace)&.macro
    assert_equal :belongs_to, Conversation.reflect_on_association(:agent)&.macro
    assert_includes Conversation.column_names, "workspace_agent_id"
    assert_nil Conversation.reflect_on_association(:agent_snapshot)
    assert_nil Conversation.reflect_on_association(:execution_runtime)
    assert_not_includes Conversation.column_names, "agent_snapshot_id"
    assert_not_includes Conversation.column_names, "execution_runtime_id"
  end

  test "requires an explicit workspace agent and supports explicit interaction lock states" do
    VALID_INTERACTION_LOCK_STATES.each do |interaction_lock_state|
      conversation = build_conversation(interaction_lock_state: interaction_lock_state)
      assert conversation.valid?, "expected interaction lock state #{interaction_lock_state.inspect} to be valid: #{conversation.errors.full_messages.to_sentence}"
    end

    installation = create_installation!
    user = create_user!(installation: installation)
    agent = create_agent!(installation: installation)
    missing_mount = Conversation.new(
      installation: installation,
      workspace: create_workspace!(installation: installation, user: user),
      agent: agent,
      user: user,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )

    assert_not missing_mount.valid?
    assert_includes missing_mount.errors[:workspace_agent], "must exist"
  end

  test "rejects creating a new conversation on a revoked workspace agent" do
    context = conversation_context
    context[:workspace_agent].update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "agent_visibility_revoked"
    )
    conversation = build_conversation

    assert_not conversation.valid?
    assert_includes conversation.errors[:workspace_agent], "must be active for new conversations"
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
    VALID_LABEL_LOCK_STATES.each do |lock_state|
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

  test "rejects invalid interaction_lock_state" do
    conversation = build_conversation(interaction_lock_state: "invalid_lock_state")

    assert_not conversation.valid?
    assert_includes conversation.errors[:interaction_lock_state], "is not included in the list"
  end

  test "defaults metadata sources and lock states on new and persisted conversation" do
    conversation = build_conversation

    assert_equal "none", conversation.title_source
    assert_equal "none", conversation.summary_source
    assert_equal "unlocked", conversation.title_lock_state
    assert_equal "unlocked", conversation.summary_lock_state
    assert_equal "mutable", conversation.interaction_lock_state

    conversation.save!
    conversation.reload

    assert_equal "none", conversation.title_source
    assert_equal "none", conversation.summary_source
    assert_equal "unlocked", conversation.title_lock_state
    assert_equal "unlocked", conversation.summary_lock_state
    assert_equal "mutable", conversation.interaction_lock_state
  end

  test "root conversations created through create_root use the localized untitled placeholder" do
    context = conversation_context

    conversation = Conversations::CreateRoot.call(
      workspace_agent: context[:workspace_agent]
    )

    assert_equal I18n.t("conversations.defaults.untitled_title"), conversation.title
    assert_equal "none", conversation.title_source
    assert_equal "unlocked", conversation.title_lock_state
    assert_equal context[:workspace_agent], conversation.workspace_agent
  end

  test "accessible_to_user keeps retained conversations visible after the mount is revoked" do
    context = conversation_context
    conversation = Conversations::CreateRoot.call(
      workspace_agent: context[:workspace_agent]
    )

    context[:workspace_agent].update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "owner_revoked"
    )

    assert_equal [conversation], Conversation.accessible_to_user(context[:workspace].user).order(:id).to_a
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

  test "rejects ready continuity without a current execution epoch" do
    context = conversation_context
    conversation = Conversations::CreateRoot.call(workspace_agent: context[:workspace_agent])
    conversation.execution_continuity_state = "ready"

    assert_not conversation.valid?
    assert_includes conversation.errors[:execution_continuity_state], "must be not_started when no current execution epoch exists"
  end

  test "rejects handoff continuity without a current execution epoch" do
    conversation = build_conversation(execution_continuity_state: "handoff_pending")

    assert_not conversation.valid?
    assert_includes conversation.errors[:execution_continuity_state], "must be not_started when no current execution epoch exists"
  end

  test "rejects not_started continuity once a current execution epoch exists" do
    context = conversation_context
    conversation = Conversations::CreateRoot.call(workspace_agent: context[:workspace_agent])
    epoch = initialize_current_execution_epoch!(conversation)

    conversation.current_execution_epoch = epoch
    conversation.current_execution_runtime = epoch.execution_runtime
    conversation.execution_continuity_state = "not_started"

    assert_not conversation.valid?
    assert_includes conversation.errors[:execution_continuity_state], "must not remain not_started after execution continuity is materialized"
  end

  private

  def build_conversation(attributes = {})
    context = conversation_context

    Conversation.new(
      {
        installation: context[:installation],
        workspace_agent: context[:workspace_agent],
        workspace: context[:workspace],
        agent: context[:agent],
        kind: "root",
        purpose: "interactive",
        lifecycle_state: "active",
        interaction_lock_state: "mutable",
      }.merge(attributes)
    )
  end

  def conversation_context
    @conversation_context ||= begin
      installation = create_installation!
      agent = create_agent!(installation: installation)
      user = create_user!(installation: installation)
      workspace = Workspace.create!(
        installation: installation,
        user: user,
        name: "Conversation Workspace",
        privacy: "private"
      )
      workspace_agent = WorkspaceAgent.create!(
        installation: installation,
        workspace: workspace,
        agent: agent
      )

      {
        installation: installation,
        workspace: workspace,
        workspace_agent: workspace_agent,
        agent: agent,
      }
    end
  end
end
