require "test_helper"

class Turns::StartAutomationTurnTest < ActiveSupport::TestCase
  test "starts an automation turn without a transcript bearing user message" do
    context = create_workspace_context!
    conversation = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    turn = Turns::StartAutomationTurn.call(
      conversation: conversation,
      origin_kind: "automation_schedule",
      origin_payload: { "cron" => "0 9 * * *" },
      source_ref_type: "AutomationSchedule",
      source_ref_id: "schedule-1",
      idempotency_key: "idemp-1",
      external_event_key: "evt-1",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: { "temperature" => 0.1 },
      resolved_model_selection_snapshot: {
        "selector_source" => "conversation",
        "normalized_selector" => "role:main",
      }
    )

    assert turn.active?
    assert turn.automation_schedule?
    assert_equal({ "cron" => "0 9 * * *" }, turn.origin_payload)
    assert_nil turn.selected_input_message
    assert_nil turn.selected_output_message
  end

  test "uses the conversation bound deployment instead of an arbitrary caller supplied deployment" do
    context = create_workspace_context!
    conversation = Conversations::CreateAutomationRoot.call(
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

    turn = Turns::StartAutomationTurn.call(
      conversation: conversation,
      origin_kind: "automation_schedule",
      origin_payload: { "cron" => "0 9 * * *" },
      source_ref_type: "AutomationSchedule",
      source_ref_id: "schedule-2",
      idempotency_key: "idemp-2",
      external_event_key: "evt-2",
      agent_deployment: alternate_deployment,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_equal conversation.agent_deployment, turn.agent_deployment
    assert_equal conversation.agent_deployment.fingerprint, turn.pinned_deployment_fingerprint
  end

  test "rejects pending delete automation conversations" do
    context = create_workspace_context!
    conversation = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartAutomationTurn.call(
        conversation: conversation,
        origin_kind: "automation_schedule",
        origin_payload: { "cron" => "0 9 * * *" },
        source_ref_type: "AutomationSchedule",
        source_ref_id: "schedule-1",
        idempotency_key: "idemp-1",
        external_event_key: "evt-1",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained for automation turn entry"
  end

  test "rechecks active lifecycle state after acquiring the conversation lock" do
    context = create_workspace_context!
    conversation = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    archive_during_lock!(conversation)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartAutomationTurn.call(
        conversation: conversation,
        origin_kind: "automation_schedule",
        origin_payload: { "cron" => "0 9 * * *" },
        source_ref_type: "AutomationSchedule",
        source_ref_id: "schedule-1",
        idempotency_key: "idemp-1",
        external_event_key: "evt-1",
        agent_deployment: context[:agent_deployment],
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active for automation turn entry"
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
