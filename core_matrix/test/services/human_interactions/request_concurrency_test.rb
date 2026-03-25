require "test_helper"

class HumanInteractions::RequestConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup { truncate_all_tables! }
  teardown { truncate_all_tables! }

  test "waits for the conversation lock and rejects opens after concurrent archival" do
    context = build_human_interaction_context!
    conversation_id = context[:conversation].id
    workflow_node_id = context[:workflow_node].id

    ready = Queue.new
    gate = Queue.new

    request_thread = Thread.new do
      Thread.current.report_on_exception = false

      ActiveRecord::Base.connection_pool.with_connection do
        workflow_node = WorkflowNode.find(workflow_node_id)
        conversation = Conversation.find(conversation_id)

        ready << true
        gate.pop

        HumanInteractions::Request.call(
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
        sleep 0.05
        conversation.update!(lifecycle_state: "archived")
      end
    end

    result = request_thread.join(10)&.value
    raise "request thread timed out" if result.nil?

    assert_instance_of ActiveRecord::RecordInvalid, result
    assert_includes result.record.errors[:lifecycle_state], "must be active before opening human interaction"
    assert_empty HumanInteractionRequest.where(conversation_id: conversation_id)
  end
end
