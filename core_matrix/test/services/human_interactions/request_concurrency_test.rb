require "test_helper"

class HumanInteractions::RequestConcurrencyTest < NonTransactionalConcurrencyTestCase
  test "waits for the conversation lock and rejects opens after concurrent archival" do
    context = build_human_interaction_context!
    conversation_id = context[:conversation].id
    workflow_node_id = context[:workflow_node].id
    lock_attempted = Queue.new
    request_service = build_lock_observed_request_service(lock_attempted)

    ready = Queue.new
    gate = Queue.new

    request_thread = Thread.new do
      Thread.current.report_on_exception = false

      ActiveRecord::Base.connection_pool.with_connection do
        workflow_node = WorkflowNode.find(workflow_node_id)
        conversation = Conversation.find(conversation_id)

        ready << true
        gate.pop

        request_service.call(
          request_type: "ApprovalRequest",
          workflow_node: workflow_node,
          blocking: true,
          request_payload: { "approval_scope" => "publish" }
        )
      rescue => error
        error
      end
    end

    ActiveRecord::Base.connection_pool.with_connection do
      conversation = Conversation.find(conversation_id)

      conversation.with_lock do
        ready.pop
        gate << true
        lock_attempted.pop
        conversation.update!(lifecycle_state: "archived")
      end
    end

    result = request_thread.join(10)&.value
    raise "request thread timed out" if result.nil?

    assert_instance_of ActiveRecord::RecordInvalid, result
    assert_includes result.record.errors[:lifecycle_state], "must be active before opening human interaction"
    assert_empty HumanInteractionRequest.where(conversation_id: conversation_id)
  end

  private

  def build_lock_observed_request_service(lock_attempted)
    Class.new(HumanInteractions::Request) do
      define_method(:with_locked_workflow_context) do |workflow_node_id, &block|
        ApplicationRecord.transaction do
          workflow_node = WorkflowNode.find(workflow_node_id)
          workflow_run = WorkflowRun.find(workflow_node.workflow_run_id)
          conversation = Conversation.find(workflow_run.conversation_id)

          lock_attempted << true

          conversation.with_lock do
            workflow_run.with_lock do
              block.call(workflow_node.reload, workflow_run.reload, conversation.reload)
            end
          end
        end
      end

      private :with_locked_workflow_context
    end
  end
end
