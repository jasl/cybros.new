require "test_helper"

class Turns::StartUserTurnTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "starts an active manual user turn with a selected input message" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )

    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Hello world",
      resolved_config_snapshot: { "temperature" => 0.2 },
      resolved_model_selection_snapshot: {
        "selector_source" => "conversation",
        "normalized_selector" => "role:main",
      }
    )

    assert turn.active?
    assert turn.manual_user?
    assert_equal 1, turn.sequence
    assert_equal "User", turn.source_ref_type
    assert_equal context[:user].public_id, turn.source_ref_id
    assert_equal context[:agent_definition_version], turn.agent_definition_version
    assert_equal conversation.current_execution_epoch, turn.execution_epoch
    assert_equal context[:execution_runtime], turn.execution_runtime
    assert_equal context[:execution_runtime].current_execution_runtime_version, turn.execution_runtime_version
    assert_equal context[:agent_definition_version].fingerprint, turn.pinned_agent_definition_fingerprint
    assert_equal(context[:agent].agent_config_state&.version || 1, turn.agent_config_version)
    assert_equal(
      context[:agent].agent_config_state&.content_fingerprint || context[:agent_definition_version].definition_fingerprint,
      turn.agent_config_content_fingerprint
    )
    assert_equal({ "temperature" => 0.2 }, turn.resolved_config_snapshot)
    assert_equal "role:main", turn.resolved_model_selection_snapshot.fetch("normalized_selector")
    assert_instance_of UserMessage, turn.selected_input_message
    assert_equal "Hello world", turn.selected_input_message.content
    assert_equal 0, turn.selected_input_message.variant_index
    assert_nil turn.selected_input_message.source_input_message
    assert_nil turn.selected_output_message
    assert_equal turn, conversation.reload.latest_turn
    assert_equal turn, conversation.latest_active_turn
    assert_equal turn.selected_input_message, conversation.latest_message
    assert_equal turn.selected_input_message.created_at.to_i, conversation.last_activity_at.to_i
  end

  test "starts a user turn within twenty-seven SQL queries" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )

    assert_sql_query_count_at_most(27) do
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Hello world",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )

      assert_equal context[:user].public_id, turn.source_ref_id
    end
  end

  test "leaves the placeholder title in place and defers bootstrap title generation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )

    assert_no_enqueued_jobs(only: Conversations::Metadata::BootstrapTitleJob) do
      Turns::StartUserTurn.call(
        conversation: conversation,
        content: "  \nPlan migration timeline.\nTrack dependencies.",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    conversation.reload
    assert_equal I18n.t("conversations.defaults.untitled_title"), conversation.title
    assert conversation.title_source_none?
  end

  test "freezes the active agent definition version instead of a caller supplied version" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    alternate_agent_definition_version = create_agent_definition_version!(
      installation: context[:installation],
      agent: create_agent!(installation: context[:installation]),
      fingerprint: "alternate-#{next_test_sequence}"
    )

    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Hello bound runtime",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_equal context[:agent_definition_version], turn.agent_definition_version
    assert_equal context[:agent_definition_version].fingerprint, turn.pinned_agent_definition_fingerprint
    refute_equal alternate_agent_definition_version, turn.agent_definition_version
  end

  test "initializes the first execution epoch directly on the overridden runtime" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    alternate_execution_runtime = create_execution_runtime!(installation: context[:installation])
    create_execution_runtime_connection!(installation: context[:installation], execution_runtime: alternate_execution_runtime)

    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Hello executor alias",
      execution_runtime: alternate_execution_runtime,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_equal alternate_execution_runtime, turn.execution_runtime
    assert_equal alternate_execution_runtime, conversation.reload.current_execution_runtime
    assert_equal alternate_execution_runtime, conversation.current_execution_epoch.execution_runtime
    assert_equal 1, conversation.execution_epochs.count
  end

  test "rejects unexpected keyword arguments" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )

    assert_raises(ArgumentError) do
      Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Hello strict contract",
        agent_definition_version: context[:agent_definition_version],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end
  end

  test "rejects automation purpose conversations" do
    context = create_workspace_context!
    conversation = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace]
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: conversation,
        content: "This should fail",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end
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
      Turns::StartUserTurn.call(
        conversation: child_conversation,
        content: "Blocked",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
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
      Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Blocked",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:entry_policy_payload], "must allow main transcript entry for user turn entry"
  end

  test "rejects pending delete conversations" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Blocked",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained for user turn entry"
  end

  test "rejects close in progress conversations before creating a user turn" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    ConversationCloseOperation.create!(
      installation: conversation.installation,
      conversation: conversation,
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Blocked by close",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:base], "must not accept new turn entry while close is in progress"
    assert_equal 0, conversation.reload.turns.count
  end

  test "rechecks active lifecycle state after acquiring the conversation lock" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    archive_during_lock!(conversation)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Blocked by archival",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active for user turn entry"
    assert_equal 0, conversation.reload.turns.count
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

  def archive_during_lock!(conversation)
    injected = false

    conversation.singleton_class.prepend(Module.new do
      define_method(:lock!) do |*args, **kwargs|
        unless injected
          injected = true
          pool = self.class.connection_pool
          connection = pool.checkout

          begin
            updated_at = Time.current

            connection.execute(<<~SQL.squish)
              UPDATE conversations
              SET lifecycle_state = 'archived',
                  updated_at = #{connection.quote(updated_at)}
              WHERE id = #{connection.quote(id)}
            SQL
          ensure
            pool.checkin(connection)
          end
        end

        super(*args, **kwargs)
      end
    end)
  end
end
