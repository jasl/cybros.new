require "test_helper"

class ChannelSessionTest < ActiveSupport::TestCase
  test "generates a public id and normalizes the thread boundary key" do
    context = channel_session_context

    session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: context[:conversation],
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "telegram-user-1",
      thread_key: nil,
      session_metadata: {}
    )

    assert session.public_id.present?
    assert_equal session, ChannelSession.find_by_public_id!(session.public_id)
    assert_equal "", session.normalized_thread_key
  end

  test "enforces one session boundary per connector peer and normalized thread key" do
    context = channel_session_context

    ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: context[:conversation],
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "telegram-user-1",
      thread_key: nil,
      session_metadata: {}
    )

    duplicate = ChannelSession.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: context[:conversation],
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "telegram-user-1",
      thread_key: "",
      session_metadata: {}
    )

    assert_not duplicate.valid?
    assert duplicate.errors[:normalized_thread_key].present? || duplicate.errors[:peer_id].present? || duplicate.errors[:base].present?
  end

  test "treats non-empty thread keys as part of the unique session boundary" do
    context = channel_session_context

    ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: context[:conversation],
      platform: "telegram",
      peer_kind: "group",
      peer_id: "telegram-group-1",
      thread_key: "topic-1",
      session_metadata: {}
    )

    duplicate_thread = ChannelSession.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: context[:conversation],
      platform: "telegram",
      peer_kind: "group",
      peer_id: "telegram-group-1",
      thread_key: "topic-1",
      session_metadata: {}
    )
    different_thread = ChannelSession.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: context[:conversation],
      platform: "telegram",
      peer_kind: "group",
      peer_id: "telegram-group-1",
      thread_key: "topic-2",
      session_metadata: {}
    )

    assert_not duplicate_thread.valid?
    assert duplicate_thread.errors[:normalized_thread_key].present? || duplicate_thread.errors[:peer_id].present? || duplicate_thread.errors[:base].present?
    assert_predicate different_thread, :valid?
  end

  test "rejects conversations mounted from a different workspace agent than the ingress binding" do
    context = channel_session_context
    other_workspace = create_workspace!(
      installation: context[:installation],
      user: context[:user],
      name: "Other Workspace"
    )
    other_workspace_agent = create_workspace_agent!(
      installation: context[:installation],
      workspace: other_workspace,
      agent: context[:agent]
    )
    other_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: other_workspace,
      workspace_agent: other_workspace_agent,
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )

    session = ChannelSession.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: other_conversation,
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "telegram-user-1",
      thread_key: nil,
      session_metadata: {}
    )

    assert_not session.valid?
    assert_includes session.errors[:conversation], "must belong to the same workspace agent as the ingress binding"
  end

  test "accepts telegram webhook as a distinct session platform" do
    context = channel_session_context(platform: "telegram_webhook")

    session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: context[:conversation],
      platform: "telegram_webhook",
      peer_kind: "dm",
      peer_id: "telegram-user-2",
      thread_key: nil,
      session_metadata: {}
    )

    assert_equal "telegram_webhook", session.platform
    assert_equal "telegram_webhook", session.channel_connector.platform
  end

  private

  def channel_session_context(platform: "telegram")
    context = create_workspace_context!
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      routing_policy_payload: {},
      manual_entry_policy: {
        "allow_app_entry" => true,
        "allow_external_entry" => true,
      }
    )
    channel_connector = ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      platform: platform,
      driver: "telegram_bot_api",
      transport_kind: transport_kind_for(platform),
      label: "Primary Telegram",
      lifecycle_state: "active",
      credential_ref_payload: {},
      config_payload: {},
      runtime_state_payload: {}
    )
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )

    context.merge(
      user: context[:user],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation
    )
  end

  def transport_kind_for(platform)
    platform == "telegram_webhook" ? "webhook" : "poller"
  end
end
