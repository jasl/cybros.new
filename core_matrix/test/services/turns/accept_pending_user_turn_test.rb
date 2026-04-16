require "test_helper"

class Turns::AcceptPendingUserTurnTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "creates a pending manual user turn and projects queued supervision state" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )

    turn = nil

    assert_no_enqueued_jobs(only: Conversations::Metadata::BootstrapTitleJob) do
      assert_difference(["Turn.count", "Message.count", "ConversationSupervisionState.count"], +1) do
        turn = Turns::AcceptPendingUserTurn.call(
          conversation: conversation,
          content: "Build a complete browser-playable React 2048 game and add automated tests.",
          selector_source: "app_api",
          selector: "candidate:codex_subscription/gpt-5.3-codex",
          execution_runtime: context[:execution_runtime]
        )
      end
    end

    assert_equal "pending", turn.workflow_bootstrap_state
    assert_equal(
      {
        "selector_source" => "app_api",
        "selector" => "candidate:codex_subscription/gpt-5.3-codex",
        "root_node_key" => "turn_step",
        "root_node_type" => "turn_step",
        "decision_source" => "system",
        "metadata" => {},
      },
      turn.workflow_bootstrap_payload
    )
    assert_equal({}, turn.workflow_bootstrap_failure_payload)
    assert turn.workflow_bootstrap_requested_at.present?
    assert_nil turn.workflow_bootstrap_started_at
    assert_nil turn.workflow_bootstrap_finished_at
    assert_equal context[:execution_runtime], turn.execution_runtime
    assert_equal conversation.reload.latest_turn, turn
    assert_equal turn.selected_input_message, conversation.latest_message
    assert_nil conversation.latest_active_workflow_run
    assert_equal "ready", conversation.execution_continuity_state
    assert conversation.current_execution_epoch.present?
    assert_equal I18n.t("conversations.defaults.untitled_title"), conversation.reload.title
    assert conversation.title_source_none?

    state = conversation.reload.conversation_supervision_state
    assert_equal "queued", state.overall_state
    assert_equal "queued", state.board_lane
    assert_equal "turn", state.current_owner_kind
    assert_equal turn.public_id, state.current_owner_public_id
    assert_equal "Build a complete browser-playable React 2048 game and add automated tests.", state.request_summary
    assert_equal turn.workflow_bootstrap_requested_at.to_i, state.last_progress_at.to_i
  end

  test "rejects agent internal only conversations" do
    context = create_workspace_context!
    root_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: root_conversation,
      kind: "fork",
      entry_policy_payload: agent_internal_entry_policy_payload
    )
    SubagentConnection.create!(
      installation: context[:installation],
      conversation: child_conversation,
      owner_conversation: root_conversation,
      user: child_conversation.user,
      workspace: child_conversation.workspace,
      agent: child_conversation.agent,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::AcceptPendingUserTurn.call(
        conversation: child_conversation,
        content: "Blocked",
        selector_source: "app_api",
        selector: "candidate:codex_subscription/gpt-5.3-codex"
      )
    end

    assert_includes error.record.errors[:entry_policy_payload], "must allow main transcript entry for user turn entry"
  end

  test "rejects channel-managed conversations even while idle" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime],
      entry_policy_payload: Conversation.channel_managed_entry_policy_payload(
        base_policy_payload: context[:workspace_agent].entry_policy_payload,
        purpose: "interactive"
      )
    )
    bind_channel_session!(context:, conversation:)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::AcceptPendingUserTurn.call(
        conversation: conversation,
        content: "Blocked",
        selector_source: "app_api",
        selector: "candidate:codex_subscription/gpt-5.3-codex"
      )
    end

    assert_includes error.record.errors[:entry_policy_payload], "must allow main transcript entry for user turn entry"
  end

  private

  def bind_channel_session!(context:, conversation:, platform: "telegram")
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      routing_policy_payload: {},
      manual_entry_policy: IngressBinding::DEFAULT_MANUAL_ENTRY_POLICY
    )
    channel_connector = ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      platform: platform,
      driver: "telegram_bot_api",
      transport_kind: platform == "telegram_webhook" ? "webhook" : "poller",
      label: "Telegram Connector",
      lifecycle_state: "active",
      credential_ref_payload: { "bot_token" => "123:abc" },
      config_payload: {},
      runtime_state_payload: {}
    )

    ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      platform: platform,
      peer_kind: "dm",
      peer_id: "42",
      thread_key: nil,
      binding_state: "active",
      session_metadata: {}
    )
  end
end
