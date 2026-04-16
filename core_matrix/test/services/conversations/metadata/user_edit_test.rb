require "test_helper"

class Conversations::Metadata::UserEditTest < ActiveSupport::TestCase
  test "editing title sets user source and lock without locking summary" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    occurred_at = Time.zone.parse("2026-04-06 11:00:00")

    Conversations::Metadata::UserEdit.call(
      conversation: conversation,
      title: "Pinned by user",
      occurred_at: occurred_at
    )

    conversation.reload
    assert_equal "Pinned by user", conversation.title
    assert_equal "user", conversation.title_source
    assert_equal "user_locked", conversation.title_lock_state
    assert_equal occurred_at, conversation.title_updated_at
    assert_equal "none", conversation.summary_source
    assert_equal "unlocked", conversation.summary_lock_state
  end

  test "editing summary sets user source and lock without locking title" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    occurred_at = Time.zone.parse("2026-04-06 11:05:00")

    Conversations::Metadata::UserEdit.call(
      conversation: conversation,
      summary: "User-authored summary",
      occurred_at: occurred_at
    )

    conversation.reload
    assert_equal "User-authored summary", conversation.summary
    assert_equal "user", conversation.summary_source
    assert_equal "user_locked", conversation.summary_lock_state
    assert_equal occurred_at, conversation.summary_updated_at
    assert_equal "none", conversation.title_source
    assert_equal "unlocked", conversation.title_lock_state
  end

  test "rejects metadata edits for channel-managed conversations" do
    context = fresh_workspace_context!
    conversation = create_channel_managed_conversation!(context)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Metadata::UserEdit.call(
        conversation: conversation,
        title: "Pinned by user"
      )
    end

    assert_includes error.record.errors[:base], "must not update conversation metadata while externally managed"
  end

  private

  def fresh_workspace_context!
    delete_all_table_rows!
    create_workspace_context!
  end

  def create_channel_managed_conversation!(context)
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
      platform: "telegram",
      driver: "telegram_bot_api",
      transport_kind: "poller",
      label: "Telegram Poller",
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
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "42",
      thread_key: nil,
      binding_state: "active",
      session_metadata: {}
    )
    conversation
  end
end
