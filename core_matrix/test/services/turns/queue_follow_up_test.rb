require "test_helper"

class Turns::QueueFollowUpTest < ActiveSupport::TestCase
  test "creates a queued follow up turn with a new selected input message" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    queued = Turns::QueueFollowUp.call(
      conversation: conversation,
      content: "Follow up input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert queued.queued?
    assert queued.manual_user?
    assert_equal 2, queued.sequence
    assert_equal "User", queued.source_ref_type
    assert_equal context[:user].public_id, queued.source_ref_id
    assert_instance_of UserMessage, queued.selected_input_message
    assert_equal "Follow up input", queued.selected_input_message.content
  end

  test "freezes the active agent snapshot instead of a caller supplied snapshot" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    alternate_agent_snapshot = create_agent_snapshot!(
      installation: context[:installation],
      agent: create_agent!(installation: context[:installation]),
      fingerprint: "alternate-#{next_test_sequence}"
    )

    queued = Turns::QueueFollowUp.call(
      conversation: conversation,
      content: "Follow up input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_equal context[:agent_snapshot], queued.agent_snapshot
    assert_equal context[:agent_snapshot].fingerprint, queued.pinned_agent_snapshot_fingerprint
    refute_equal alternate_agent_snapshot, queued.agent_snapshot
  end

  test "rejects queueing when no active work exists" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::QueueFollowUp.call(
        conversation: conversation,
        content: "Should not queue",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end
  end

  test "rejects automation purpose conversations with follow up turn entry messaging" do
    context = create_workspace_context!
    conversation = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::QueueFollowUp.call(
        conversation: conversation,
        content: "Should not queue",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:purpose], "must be interactive for follow up turn entry"
  end

  test "rejects queueing follow up on agent addressable conversations before active work checks" do
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
      Turns::QueueFollowUp.call(
        conversation: child_conversation,
        content: "Blocked",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:addressability], "must be owner_addressable for follow up turn entry"
  end

  test "rejects queueing follow up on a pending delete conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::QueueFollowUp.call(
        conversation: conversation,
        content: "Should not queue",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained for follow up turn entry"
  end

  test "rechecks active lifecycle state after acquiring the conversation lock" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    archive_during_lock!(conversation)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::QueueFollowUp.call(
        conversation: conversation,
        content: "Blocked follow up",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active for follow up turn entry"
    assert_equal 1, conversation.reload.turns.count
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
