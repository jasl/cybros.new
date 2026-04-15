require "test_helper"

class Conversations::CreateRootTest < ActiveSupport::TestCase
  test "creates an active interactive root conversation with a self closure" do
    context = create_workspace_context!

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )

    assert_equal context[:installation], conversation.installation
    assert_equal context[:workspace], conversation.workspace
    assert conversation.root?
    assert conversation.interactive?
    assert conversation.active?
    assert conversation.retained?
    assert_nil conversation.parent_conversation
    assert_nil conversation.historical_anchor_message_id
    assert_equal context[:execution_runtime], conversation.current_execution_runtime
    assert_nil conversation.current_execution_epoch
    assert_equal 0, conversation.execution_epochs.count
    assert_equal "not_started", conversation.execution_continuity_state
    assert_equal I18n.t("conversations.defaults.untitled_title"), conversation.title
    assert conversation.title_source_none?
    assert conversation.title_lock_state_unlocked?
    assert_nil conversation.lineage_store_reference
    assert_equal [[conversation.id, conversation.id, 0]],
      ConversationClosure.where(descendant_conversation: conversation)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)
  end

  test "accepts an explicit initial execution runtime override" do
    context = create_workspace_context!
    override_runtime = create_execution_runtime!(installation: context[:installation], display_name: "Cloud Runtime")
    create_execution_runtime_connection!(installation: context[:installation], execution_runtime: override_runtime)

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: override_runtime
    )

    assert_equal override_runtime, conversation.current_execution_runtime
    assert_nil conversation.current_execution_epoch
    assert_equal "not_started", conversation.execution_continuity_state
    assert_equal I18n.t("conversations.defaults.untitled_title"), conversation.title
    assert conversation.title_source_none?
    assert conversation.title_lock_state_unlocked?
  end

  test "sets empty root-conversation anchor state directly" do
    context = create_workspace_context!

    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert_predicate conversation, :persisted?
    assert_equal conversation.created_at.to_i, conversation.last_activity_at.to_i
    assert_nil conversation.latest_turn
    assert_nil conversation.latest_active_turn
    assert_nil conversation.latest_message
    assert_nil conversation.latest_active_workflow_run
  end

  test "projects capability defaults from workspace agent capability policy payload" do
    context = create_workspace_context!
    context[:workspace_agent].update!(
      capability_policy_payload: {
        "disabled_capabilities" => %w[supervision],
      }
    )

    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    refute conversation.supervision_enabled?
    refute conversation.detailed_progress_enabled?
    refute conversation.side_chat_enabled?
    refute conversation.control_enabled?
  end

  test "falls back to the mounted agent default execution runtime when the mount has no runtime" do
    installation = create_installation!
    user = create_user!(installation: installation)
    primary_runtime = create_execution_runtime!(installation: installation, display_name: "Primary Mount Runtime")
    mounted_agent_runtime = create_execution_runtime!(installation: installation, display_name: "Mounted Agent Runtime")
    create_execution_runtime_connection!(installation: installation, execution_runtime: primary_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: mounted_agent_runtime)

    primary_agent = create_agent!(installation: installation, default_execution_runtime: primary_runtime)
    mounted_agent = create_agent!(installation: installation, default_execution_runtime: mounted_agent_runtime)
    workspace = create_workspace!(installation: installation, user: user, name: "Multi Mount Workspace")
    create_workspace_agent!(
      installation: installation,
      workspace: workspace,
      agent: primary_agent,
      default_execution_runtime: primary_runtime
    )
    mounted_workspace_agent = create_workspace_agent!(
      installation: installation,
      workspace: workspace,
      agent: mounted_agent,
      default_execution_runtime: nil
    )

    conversation = Conversations::CreateRoot.call(workspace_agent: mounted_workspace_agent)

    assert_equal mounted_workspace_agent, conversation.workspace_agent
    assert_equal mounted_agent_runtime, conversation.current_execution_runtime
  end
end
