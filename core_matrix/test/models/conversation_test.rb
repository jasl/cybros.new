require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    assert conversation.public_id.present?
    assert_equal conversation, Conversation.find_by_public_id!(conversation.public_id)
  end

  test "binds to one execution environment and rejects a deployment from another environment" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent_installation = create_agent_installation!(installation: installation)
    first = create_execution_environment!(
      installation: installation,
      environment_fingerprint: "host-a",
      capability_payload: {}
    )
    second = create_execution_environment!(
      installation: installation,
      environment_fingerprint: "host-b",
      capability_payload: {}
    )
    deployment = create_agent_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: second
    )
    binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent_installation: agent_installation
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding
    )

    conversation = Conversation.new(
      installation: installation,
      workspace: workspace,
      execution_environment: first,
      agent_deployment: deployment,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )

    assert_not conversation.valid?
    assert_includes conversation.errors[:agent_deployment], "must belong to the bound execution environment"
  end

  test "belongs to workspace and not directly to an agent installation" do
    assert_equal :belongs_to, Conversation.reflect_on_association(:workspace).macro
    assert_nil Conversation.reflect_on_association(:agent_installation)
    assert_not_includes Conversation.column_names, "agent_installation_id"
  end

  test "does not expose runtime contract readers on the model" do
    conversation = Conversation.new

    refute_respond_to conversation, :runtime_contract
    refute_respond_to conversation, :conversation_attachment_upload?
  end

  test "supports owner and agent addressability" do
    assert_respond_to Conversation, :addressabilities
    assert_includes Conversation.addressabilities.keys, "owner_addressable"
    assert_includes Conversation.addressabilities.keys, "agent_addressable"

    context = create_workspace_context!
    default_conversation = create_conversation_record!(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: default_conversation,
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      kind: "fork",
      addressability: "agent_addressable"
    )

    assert_equal "owner_addressable", default_conversation.addressability
    assert_equal "agent_addressable", child_conversation.addressability
  end

  test "enforces conversation kind rules" do
    context = create_workspace_context!
    root_anchor_turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
        workspace: context[:workspace],
        execution_environment: context[:execution_environment],
        agent_deployment: context[:agent_deployment]
      ),
      content: "Root anchor",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    root = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )
    branch_without_parent = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      kind: "branch",
      purpose: "interactive",
      lifecycle_state: "active",
      historical_anchor_message_id: root_anchor_turn.selected_input_message_id
    )
    checkpoint_without_anchor = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
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

  test "requires child historical anchors to belong to the parent conversation history" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    foreign_root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    foreign_turn = Turns::StartUserTurn.call(
      conversation: foreign_root,
      content: "Foreign anchor",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    branch = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      parent_conversation: root,
      kind: "branch",
      purpose: "interactive",
      lifecycle_state: "active",
      historical_anchor_message_id: foreign_turn.selected_input_message_id
    )

    assert_not branch.valid?
    assert_includes branch.errors[:historical_anchor_message_id], "must belong to the parent conversation history"
  end

  test "accepts a historical anchor inherited into the parent transcript history" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root anchor",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )

    checkpoint = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      parent_conversation: branch,
      kind: "checkpoint",
      purpose: "interactive",
      lifecycle_state: "active",
      historical_anchor_message_id: root_turn.selected_input_message_id
    )

    assert checkpoint.valid?
  end

  test "enforces automation conversations as root only" do
    context = create_workspace_context!
    automation_persisted_root = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    automation_anchor_turn = Turns::StartAutomationTurn.call(
      conversation: automation_persisted_root,
      origin_kind: "system_internal",
      origin_payload: {},
      source_ref_type: "AgentDeployment",
      source_ref_id: context[:agent_deployment].public_id,
      idempotency_key: "automation-model-anchor",
      external_event_key: "automation-model-anchor",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    automation_anchor = attach_selected_output!(automation_anchor_turn, content: "Automation output")

    automation_root = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      kind: "root",
      purpose: "automation",
      lifecycle_state: "active"
    )
    automation_branch = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      kind: "branch",
      purpose: "automation",
      lifecycle_state: "active",
      parent_conversation: automation_root,
      historical_anchor_message_id: automation_anchor.id
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
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
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
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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
      kind: "fork",
      purpose: "interactive",
      lifecycle_state: "active"
    )

    assert_not child.valid?
    assert_includes child.errors[:workspace], "must match the parent conversation workspace"
  end

  test "batches visibility lookups for descendant context projections" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

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
      assert_equal 6, Conversations::ContextProjection.call(conversation: branch).messages.size
    end

    refute_respond_to branch, :context_projection_messages
    assert_operator queries.size, :<=, 2
  end

  test "raises when a persisted child conversation carries an invalid historical anchor" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(anchor_turn, content: "Root output")
    foreign_root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    foreign_turn = Turns::StartUserTurn.call(
      conversation: foreign_root,
      content: "Foreign input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    invalid_branch = Conversation.new(
      installation: context[:installation],
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      parent_conversation: root,
      kind: "branch",
      purpose: "interactive",
      lifecycle_state: "active",
      historical_anchor_message_id: foreign_turn.selected_input_message_id
    )
    invalid_branch.save!(validate: false)

    refute_respond_to invalid_branch, :transcript_projection_messages
    assert_raises(ActiveRecord::RecordNotFound) { Conversations::TranscriptProjection.call(conversation: invalid_branch.reload) }
  end

  test "detects active turns locally and across descendants when requested" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    child = Conversations::CreateFork.call(parent: root)

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
