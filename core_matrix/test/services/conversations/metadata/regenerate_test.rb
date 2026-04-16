require "test_helper"

class Conversations::Metadata::RegenerateTest < ActiveSupport::TestCase
  test "preserves user locks during generation and unlocks only the targeted field on success" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    conversation.update!(
      title: "Pinned title",
      title_source: "user",
      title_lock_state: "user_locked",
      summary: "Pinned summary",
      summary_source: "user",
      summary_lock_state: "user_locked"
    )

    occurred_at = Time.zone.parse("2026-04-06 11:15:00")
    observed = {}
    lock_depth = 0

    original_lock = Conversations::WithConversationEntryLock.method(:call)
    Conversations::WithConversationEntryLock.singleton_class.send(:define_method, :call) do |**kwargs, &block|
      lock_depth += 1
      begin
        original_lock.call(**kwargs, &block)
      ensure
        lock_depth -= 1
      end
    end
    original_call = Conversations::Metadata::GenerateField.method(:call)
    Conversations::Metadata::GenerateField.singleton_class.send(:define_method, :call) do |conversation:, field:, occurred_at: _, persist: true, **_kwargs|
      current = conversation.reload
      observed[:field] = field
      observed[:persist] = persist
      observed[:lock_depth] = lock_depth
      observed[:title_lock_state] = current.title_lock_state
      observed[:summary_lock_state] = current.summary_lock_state

      "Generated title"
    end

    begin
      Conversations::Metadata::Regenerate.call(
        conversation: conversation,
        field: :title,
        occurred_at: occurred_at
      )
    ensure
      Conversations::Metadata::GenerateField.singleton_class.send(:define_method, :call, original_call)
      Conversations::WithConversationEntryLock.singleton_class.send(:define_method, :call, original_lock)
    end

    assert_equal "title", observed[:field]
    assert_equal false, observed[:persist]
    assert_equal 0, observed[:lock_depth]
    assert_equal "user_locked", observed[:title_lock_state]
    assert_equal "user_locked", observed[:summary_lock_state]

    conversation.reload
    assert_equal "Generated title", conversation.title
    assert_equal "generated", conversation.title_source
    assert_equal "unlocked", conversation.title_lock_state
    assert_equal "Pinned summary", conversation.summary
    assert_equal "user_locked", conversation.summary_lock_state
  end

  test "restores the prior user lock state when generation fails" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    conversation.update!(
      title: "Pinned title",
      title_source: "user",
      title_lock_state: "user_locked"
    )

    original_call = Conversations::Metadata::GenerateField.method(:call)
    Conversations::Metadata::GenerateField.singleton_class.send(:define_method, :call) do |conversation:, field: _, occurred_at: _, persist: _, **_kwargs|
      conversation.errors.add(:title, "generation is unavailable")
      raise ActiveRecord::RecordInvalid, conversation
    end

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Metadata::Regenerate.call(
        conversation: conversation,
        field: :title,
        occurred_at: Time.zone.parse("2026-04-06 11:25:00")
      )
    end

    assert_includes error.record.errors.full_messages, "Title generation is unavailable"
    assert_equal "user_locked", conversation.reload.title_lock_state
    assert_equal "Pinned title", conversation.title
  ensure
    Conversations::Metadata::GenerateField.singleton_class.send(:define_method, :call, original_call)
  end

  test "does not overwrite concurrent agent updates that land while regeneration is in progress" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    conversation.update!(
      title: "Pinned title",
      title_source: "user",
      title_lock_state: "user_locked",
      title_updated_at: Time.zone.parse("2026-04-06 11:00:00")
    )

    original_call = Conversations::Metadata::GenerateField.method(:call)
    Conversations::Metadata::GenerateField.singleton_class.send(:define_method, :call) do |conversation:, field: _, occurred_at: _, persist: _, **_kwargs|
      conversation.update!(
        title: "Agent updated title",
        title_source: "agent",
        title_updated_at: Time.zone.parse("2026-04-06 11:10:00")
      )
      "Generated title"
    end

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Metadata::Regenerate.call(
        conversation: conversation,
        field: :title,
        occurred_at: Time.zone.parse("2026-04-06 11:25:00")
      )
    end

    assert_includes error.record.errors.full_messages, "Title changed while regeneration was in progress"

    conversation.reload
    assert_equal "Agent updated title", conversation.title
    assert_equal "agent", conversation.title_source
    assert_equal "user_locked", conversation.title_lock_state
  ensure
    Conversations::Metadata::GenerateField.singleton_class.send(:define_method, :call, original_call)
  end

  test "rejects regeneration for channel-managed conversations" do
    context = fresh_workspace_context!
    conversation = create_channel_managed_conversation!(context)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Metadata::Regenerate.call(
        conversation: conversation,
        field: :title,
        occurred_at: Time.zone.parse("2026-04-06 11:35:00")
      )
    end

    assert_includes error.record.errors[:base], "must not regenerate conversation metadata while externally managed"
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
