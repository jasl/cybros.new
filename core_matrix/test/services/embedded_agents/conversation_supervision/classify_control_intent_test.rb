require "test_helper"

class EmbeddedAgents::ConversationSupervision::ClassifyControlIntentTest < ActiveSupport::TestCase
  test "maps high-confidence control phrases onto bounded control verbs" do
    stop = EmbeddedAgents::ConversationSupervision::ClassifyControlIntent.call(question: "stop")
    close = EmbeddedAgents::ConversationSupervision::ClassifyControlIntent.call(question: "关闭这个任务")
    child = EmbeddedAgents::ConversationSupervision::ClassifyControlIntent.call(question: "让子任务停下")
    resume = EmbeddedAgents::ConversationSupervision::ClassifyControlIntent.call(question: "resume the waiting workflow")
    retry_step = EmbeddedAgents::ConversationSupervision::ClassifyControlIntent.call(question: "重试这一步")

    assert stop.matched?
    assert_equal "request_turn_interrupt", stop.request_kind
    assert_equal "request_conversation_close", close.request_kind
    assert_equal "request_subagent_close", child.request_kind
    assert_equal "resume_waiting_workflow", resume.request_kind
    assert_equal "retry_blocked_step", retry_step.request_kind
  end

  test "leaves ambiguous language in ordinary side-chat mode" do
    ambiguous = EmbeddedAgents::ConversationSupervision::ClassifyControlIntent.call(
      question: "Should we stop after the child comes back?"
    )
    hypothetical_stop = EmbeddedAgents::ConversationSupervision::ClassifyControlIntent.call(
      question: "如果我说“快住手”会怎样？"
    )
    hypothetical_close = EmbeddedAgents::ConversationSupervision::ClassifyControlIntent.call(
      question: "我们是不是应该“关闭这个任务”？"
    )

    refute ambiguous.matched?
    assert_nil ambiguous.request_kind
    refute hypothetical_stop.matched?
    assert_nil hypothetical_stop.request_kind
    refute hypothetical_close.matched?
    assert_nil hypothetical_close.request_kind
  end
end
