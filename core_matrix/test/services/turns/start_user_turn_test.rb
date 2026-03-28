require "test_helper"

class Turns::StartUserTurnTest < ActiveSupport::TestCase
  test "starts an active manual user turn with a selected input message" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Hello world",
      agent_deployment: context[:agent_deployment],
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
    assert_equal context[:agent_deployment].fingerprint, turn.pinned_deployment_fingerprint
    assert_equal({ "temperature" => 0.2 }, turn.resolved_config_snapshot)
    assert_equal "role:main", turn.resolved_model_selection_snapshot.fetch("normalized_selector")
    assert_instance_of UserMessage, turn.selected_input_message
    assert_equal "Hello world", turn.selected_input_message.content
    assert_nil turn.selected_output_message
  end

  test "uses the conversation bound deployment instead of an arbitrary caller supplied deployment" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    alternate_deployment = create_agent_deployment!(
      installation: context[:installation],
      agent_installation: create_agent_installation!(installation: context[:installation]),
      execution_environment: context[:execution_environment],
      fingerprint: "alternate-#{next_test_sequence}",
      bootstrap_state: "pending"
    )

    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Hello bound runtime",
      agent_deployment: alternate_deployment,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_equal conversation.agent_deployment, turn.agent_deployment
    assert_equal conversation.agent_deployment.fingerprint, turn.pinned_deployment_fingerprint
  end

  test "rejects automation purpose conversations" do
    context = create_workspace_context!
    conversation = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: conversation,
        content: "This should fail",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end
  end

  test "rejects agent addressable conversations" do
    context = create_workspace_context!
    root_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: root_conversation,
      kind: "thread",
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      addressability: "agent_addressable"
    )
    SubagentSession.create!(
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
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:addressability], "must be owner_addressable for user turn entry"
  end

  test "rejects pending delete conversations" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Blocked",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained for user turn entry"
  end

  test "rechecks active lifecycle state after acquiring the conversation lock" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    archive_during_lock!(conversation)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Blocked by archival",
        agent_deployment: context[:agent_deployment],
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
