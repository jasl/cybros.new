require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    conversation = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])

    assert conversation.public_id.present?
    assert_equal conversation, Conversation.find_by_public_id!(conversation.public_id)
  end

  test "belongs to workspace and not directly to an agent installation" do
    assert_equal :belongs_to, Conversation.reflect_on_association(:workspace).macro
    assert_nil Conversation.reflect_on_association(:agent_installation)
    assert_not_includes Conversation.column_names, "agent_installation_id"
  end

  test "enforces conversation kind rules" do
    context = create_workspace_context!

    root = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )
    branch_without_parent = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      kind: "branch",
      purpose: "interactive",
      lifecycle_state: "active",
      historical_anchor_message_id: 101
    )
    checkpoint_without_anchor = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      kind: "checkpoint",
      purpose: "interactive",
      lifecycle_state: "active",
      parent_conversation: root
    )

    assert root.valid?
    assert_not branch_without_parent.valid?
    assert_includes branch_without_parent.errors[:parent_conversation], "must exist"
    assert_not checkpoint_without_anchor.valid?
    assert_includes checkpoint_without_anchor.errors[:historical_anchor_message_id], "must exist"
  end

  test "enforces automation conversations as root only" do
    context = create_workspace_context!

    automation_root = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      kind: "root",
      purpose: "automation",
      lifecycle_state: "active"
    )
    automation_branch = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      kind: "branch",
      purpose: "automation",
      lifecycle_state: "active",
      parent_conversation: automation_root,
      historical_anchor_message_id: 101
    )

    assert automation_root.valid?
    assert_not automation_branch.valid?
    assert_includes automation_branch.errors[:kind], "must be root for automation conversations"
  end

  test "supports deletion states and deletion timestamps" do
    context = create_workspace_context!

    pending_delete = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active",
      deletion_state: "pending_delete",
      deleted_at: Time.current
    )
    deleted_without_timestamp = pending_delete.dup
    deleted_without_timestamp.deletion_state = "deleted"
    deleted_without_timestamp.deleted_at = nil

    assert pending_delete.valid?
    assert deleted_without_timestamp.invalid?
    assert_includes deleted_without_timestamp.errors[:deleted_at], "must exist once deletion is requested"
  end

  test "requires child conversations to stay in the parent workspace" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(workspace: context[:workspace])
    other_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      user_agent_binding: context[:user_agent_binding],
      name: "Other Workspace"
    )

    child = Conversation.new(
      installation: context[:installation],
      workspace: other_workspace,
      parent_conversation: root,
      kind: "thread",
      purpose: "interactive",
      lifecycle_state: "active"
    )

    assert_not child.valid?
    assert_includes child.errors[:workspace], "must match the parent conversation workspace"
  end

  test "batches visibility lookups for descendant context projections" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(workspace: context[:workspace])

    3.times do |index|
      turn = Turns::StartUserTurn.call(
        conversation: root,
        content: "Root input #{index + 1}",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
      attach_selected_output!(turn, content: "Root output #{index + 1}")
    end

    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: root.turns.order(:sequence).last.selected_output_message_id
    )

    queries = capture_visibility_queries do
      assert_equal 6, branch.context_projection_messages.size
    end

    assert_operator queries.size, :<=, 2
  end

  test "detects active turns locally and across descendants when requested" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(workspace: context[:workspace])
    child = Conversations::CreateThread.call(parent: root)

    Turns::StartUserTurn.call(
      conversation: child,
      content: "Child still running",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_not root.active_turn_exists?
    assert root.active_turn_exists?(include_descendants: true)
    assert child.active_turn_exists?
  end

  private

  def capture_visibility_queries
    queries = []
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql]
      next if sql.blank?
      next unless sql.include?("\"conversation_message_visibilities\"")

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      yield
    end

    queries
  end
end
