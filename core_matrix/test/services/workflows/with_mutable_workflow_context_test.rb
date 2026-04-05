require "test_helper"

class Workflows::WithMutableWorkflowContextTest < ActiveSupport::TestCase
  test "yields the mutable conversation alongside refreshed workflow context" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    Conversation.find(workflow_run.conversation_id).update!(override_payload: { "mode" => "fresh" })
    WorkflowRun.find(workflow_run.id).update!(
      resume_policy: "re_enter_agent",
      resume_batch_id: "checkpoint-fresh"
    )
    Turn.find(workflow_run.turn_id).update!(origin_payload: { "lock_state" => "fresh" })
    yielded = nil

    Workflows::WithMutableWorkflowContext.call(
      workflow_run: workflow_run,
      retained_message: "must be retained before mutating the workflow",
      active_message: "must be active before mutating the workflow",
      closing_message: "must not mutate the workflow while close is in progress"
    ) do |conversation, current_workflow_run, current_turn|
      yielded = [conversation, current_workflow_run, current_turn]
    end

    assert_equal workflow_run.conversation_id, yielded[0].id
    assert_equal({ "mode" => "fresh" }, yielded[0].override_payload)
    assert_equal "checkpoint-fresh", yielded[1].resume_batch_id
    assert_equal({ "lock_state" => "fresh" }, yielded[2].origin_payload)
  end

  test "rechecks mutable state after acquiring the conversation lock" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    request_deletion_during_lock!(workflow_run.conversation)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::WithMutableWorkflowContext.call(
        workflow_run: workflow_run,
        retained_message: "must be retained before mutating the workflow",
        active_message: "must be active before mutating the workflow",
        closing_message: "must not mutate the workflow while close is in progress"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before mutating the workflow"
  end

  private

  def request_deletion_during_lock!(conversation)
    injected = false

    conversation.singleton_class.prepend(Module.new do
      define_method(:lock!) do |*args, **kwargs|
        unless injected
          injected = true
          pool = self.class.connection_pool
          connection = pool.checkout

          begin
            deleted_at = Time.current

            connection.execute(<<~SQL.squish)
              UPDATE conversations
              SET deletion_state = 'pending_delete',
                  deleted_at = #{connection.quote(deleted_at)},
                  updated_at = #{connection.quote(deleted_at)}
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
