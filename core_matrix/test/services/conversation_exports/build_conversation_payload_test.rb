require "test_helper"

class ConversationExportsBuildConversationPayloadTest < ActiveSupport::TestCase
  setup do
    truncate_all_tables!
  end

  test "builds a public-id-only payload with message-bound attachments" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Export me",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_message_attachment!(
      message: turn.selected_input_message,
      filename: "input.txt",
      body: "input attachment"
    )
    output_message = attach_selected_output!(turn, content: "Here is the exported answer")
    output_attachment = create_message_attachment!(
      message: output_message,
      filename: "output.txt",
      body: "output attachment"
    )
    output_attachment.file.blob.update!(
      metadata: output_attachment.file.blob.metadata.merge(
        "publication_role" => "primary_deliverable",
        "source_kind" => "runtime_generated"
      )
    )
    conversation.update!(
      summary: "Export summary",
      summary_source: "agent"
    )

    payload = ConversationExports::BuildConversationPayload.call(conversation: conversation)

    assert_equal "conversation_export", payload.fetch("bundle_kind")
    assert_equal "2026-04-16", payload.fetch("bundle_version")
    assert_equal conversation.public_id, payload.dig("conversation", "public_id")
    assert_equal I18n.t("conversations.defaults.untitled_title"), payload.dig("conversation", "title")
    assert_equal "Export summary", payload.dig("conversation", "summary")
    assert_equal "none", payload.dig("conversation", "title_source")
    assert_equal "agent", payload.dig("conversation", "summary_source")
    assert_equal "mutable", payload.dig("conversation", "interaction_lock_state")
    assert_equal default_interactive_entry_policy_payload, payload.dig("conversation", "entry_policy_payload")
    assert_equal [], payload.fetch("delegation_summary")
    refute payload.fetch("conversation").key?("addressability")
    assert_equal 2, payload.fetch("messages").length

    input_message = payload.fetch("messages").find { |message| message.fetch("message_public_id") == turn.selected_input_message.public_id }
    output_payload = payload.fetch("messages").find { |message| message.fetch("message_public_id") == output_message.public_id }

    assert_equal "user", input_message.fetch("role")
    assert_equal "agent", output_payload.fetch("role")
    assert_equal "user_upload", input_message.fetch("attachments").first.fetch("kind")
    assert_equal "generated_output", output_payload.fetch("attachments").first.fetch("kind")
    assert_equal "primary_deliverable", output_payload.fetch("attachments").first.fetch("publication_role")
    assert_equal "runtime_generated", output_payload.fetch("attachments").first.fetch("source_kind")
    assert_match(/\Afiles\//, input_message.fetch("attachments").first.fetch("relative_path"))
    assert_match(/\Afiles\//, output_payload.fetch("attachments").first.fetch("relative_path"))

    json = JSON.generate(payload)
    refute_includes json, %("#{conversation.id}")
    refute_includes json, %("#{turn.id}")
  end

  test "includes a compact delegation summary with profile facts and public ids only" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Use a specialist",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: conversation,
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      kind: "fork",
      entry_policy_payload: agent_internal_entry_policy_payload
    )
    session = SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: conversation,
      conversation: child_conversation,
      user: child_conversation.user,
      workspace: child_conversation.workspace,
      agent: child_conversation.agent,
      origin_turn: turn,
      scope: "turn",
      profile_key: "researcher",
      resolved_model_selector_hint: "role:researcher",
      depth: 0,
      close_state: "closed",
      close_reason_kind: "turn_interrupt",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now,
      close_acknowledged_at: Time.current,
      observed_status: "completed",
      close_outcome_kind: "graceful"
    )

    payload = ConversationExports::BuildConversationPayload.call(conversation: conversation)

    assert_equal [
      {
        "subagent_connection_id" => session.public_id,
        "origin_turn_id" => turn.public_id,
        "profile_key" => "researcher",
        "close_outcome_kind" => "graceful",
      },
    ], payload.fetch("delegation_summary")
    refute payload.fetch("delegation_summary").first.key?("resolved_model_selector_hint")

    json = JSON.generate(payload)
    refute_includes json, %("#{session.id}")
    refute_includes json, %("#{child_conversation.id}")
  end

  test "includes management projection for channel-managed conversations" do
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
    channel_session = ChannelSession.create!(
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

    payload = ConversationExports::BuildConversationPayload.call(conversation: conversation)

    assert_equal true, payload.dig("conversation", "management", "managed")
    assert_equal "channel_ingress", payload.dig("conversation", "management", "manager_kind")
    assert_equal [channel_session.public_id], payload.dig("conversation", "management", "channel_session_ids")
    assert_equal [ingress_binding.public_id], payload.dig("conversation", "management", "ingress_binding_ids")
    assert_equal ["telegram"], payload.dig("conversation", "management", "platforms")

    json = JSON.generate(payload)
    refute_includes json, %("#{channel_session.id}")
    refute_includes json, %("#{ingress_binding.id}")
  end

  test "preloads transcript and attachments without query explosion" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Export query budget input 1",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_source_attachment = create_message_attachment!(
      message: first_turn.selected_input_message,
      filename: "input-1.txt",
      body: "first attachment"
    )
    first_output_message = attach_selected_output!(first_turn, content: "First exported answer")
    create_message_attachment!(
      message: first_output_message,
      origin_attachment: first_source_attachment,
      filename: "output-1.txt",
      body: "first derived attachment"
    )

    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Export query budget input 2",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_source_attachment = create_message_attachment!(
      message: second_turn.selected_input_message,
      filename: "input-2.txt",
      body: "second attachment"
    )
    second_output_message = attach_selected_output!(second_turn, content: "Second exported answer")
    create_message_attachment!(
      message: second_output_message,
      origin_attachment: second_source_attachment,
      filename: "output-2.txt",
      body: "second derived attachment"
    )

    queries = capture_sql_queries do
      ConversationExports::BuildConversationPayload.call(conversation: conversation)
    end

    assert_operator queries.length, :<=, 30, "Expected conversation export payload to stay under 30 SQL queries, got #{queries.length}:\n#{queries.join("\n")}"
  end
end
