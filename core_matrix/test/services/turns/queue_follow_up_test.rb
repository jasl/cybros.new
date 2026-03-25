require "test_helper"

class Turns::QueueFollowUpTest < ActiveSupport::TestCase
  test "creates a queued follow up turn with a new selected input message" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    queued = Turns::QueueFollowUp.call(
      conversation: conversation,
      content: "Follow up input",
      agent_deployment: context[:agent_deployment],
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

  test "rejects queueing when no active work exists" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::QueueFollowUp.call(
        conversation: conversation,
        content: "Should not queue",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end
  end

  test "rejects queueing follow up on a pending delete conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::QueueFollowUp.call(
        conversation: conversation,
        content: "Should not queue",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained for follow up turn entry"
  end

  test "rechecks active lifecycle state after acquiring the conversation lock" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    archive_during_lock!(conversation)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::QueueFollowUp.call(
        conversation: conversation,
        content: "Blocked follow up",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active for user turn entry"
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
