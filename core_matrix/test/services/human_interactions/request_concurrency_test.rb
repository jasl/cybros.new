require "test_helper"
require "timeout"

module RequestConcurrencyConversationLockObserver
  def with_lock(*args, **kwargs, &block)
    observer = Thread.current[:request_concurrency_lock_observer]
    observed_conversation_id = Thread.current[:request_concurrency_conversation_id]

    observer << true if observer && id == observed_conversation_id

    super
  end
end

Conversation.prepend(RequestConcurrencyConversationLockObserver) unless Conversation < RequestConcurrencyConversationLockObserver

class HumanInteractions::RequestConcurrencyTest < NonTransactionalConcurrencyTestCase
  test "waits for the conversation lock and rejects opens after concurrent archival" do
    context = build_human_interaction_context!
    conversation_id = context[:conversation].id
    workflow_node_id = context[:workflow_node].id
    lock_attempted = Queue.new

    ready = Queue.new
    gate = Queue.new

    request_thread = Thread.new do
      Thread.current.report_on_exception = false
      Thread.current[:request_concurrency_lock_observer] = lock_attempted
      Thread.current[:request_concurrency_conversation_id] = conversation_id

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
      ensure
        Thread.current[:request_concurrency_lock_observer] = nil
        Thread.current[:request_concurrency_conversation_id] = nil
      end
    end

    ActiveRecord::Base.connection_pool.with_connection do
      conversation = Conversation.find(conversation_id)

      conversation.with_lock do
        wait_for_signal!(ready, message: "request thread did not start")
        gate << true
        wait_for_signal!(lock_attempted, message: "request thread never attempted conversation lock")
        conversation.update!(lifecycle_state: "archived")
      end
    end

    result = request_thread.join(10)&.value
    raise "request thread timed out" if result.nil?

    assert_instance_of ActiveRecord::RecordInvalid, result
    assert_includes result.record.errors[:lifecycle_state], "must be active before opening human interaction"
    assert_empty HumanInteractionRequest.where(conversation_id: conversation_id)
  ensure
    next unless request_thread&.alive?

    request_thread.kill
    request_thread.join
  end

  private

  def wait_for_signal!(queue, timeout: 1, message:)
    Timeout.timeout(timeout, RuntimeError, message) { queue.pop }
  end
end
