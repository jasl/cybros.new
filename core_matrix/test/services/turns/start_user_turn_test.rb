require "test_helper"

class Turns::StartUserTurnTest < ActiveSupport::TestCase
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
    assert_equal context[:agent_snapshot], turn.agent_snapshot
    assert_equal context[:execution_runtime], turn.execution_runtime
    assert_equal context[:agent_snapshot].fingerprint, turn.pinned_agent_snapshot_fingerprint
    assert_equal({ "temperature" => 0.2 }, turn.resolved_config_snapshot)
    assert_equal "role:main", turn.resolved_model_selection_snapshot.fetch("normalized_selector")
    assert_instance_of UserMessage, turn.selected_input_message
    assert_equal "Hello world", turn.selected_input_message.content
    assert_equal 0, turn.selected_input_message.variant_index
    assert_nil turn.selected_input_message.source_input_message
    assert_nil turn.selected_output_message
  end

  test "bootstraps conversation title through the start user turn path" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )

    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "  \nPlan migration timeline.\nTrack dependencies.",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    conversation.reload
    assert_equal "Plan migration timeline.", conversation.title
    assert_equal "bootstrap", conversation.title_source
    assert_not_nil conversation.title_updated_at
  end

  test "freezes the active agent snapshot instead of a caller supplied snapshot" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    alternate_agent_snapshot = create_agent_snapshot!(
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

    assert_equal context[:agent_snapshot], turn.agent_snapshot
    assert_equal context[:agent_snapshot].fingerprint, turn.pinned_agent_snapshot_fingerprint
    refute_equal alternate_agent_snapshot, turn.agent_snapshot
  end

  test "accepts execution_runtime as an alias for the selected executor" do
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

  test "rejects agent addressable conversations" do
    context = create_workspace_context!
    root_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: root_conversation,
      kind: "fork",
      addressability: "agent_addressable"
    )
    SubagentConnection.create!(
      installation: context[:installation],
      conversation: child_conversation,
      owner_conversation: root_conversation,
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

    assert_includes error.record.errors[:addressability], "must be owner_addressable for user turn entry"
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
