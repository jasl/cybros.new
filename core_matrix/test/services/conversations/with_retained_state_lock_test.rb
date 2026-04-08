require "test_helper"

class Conversations::WithRetainedStateLockTest < ActiveSupport::TestCase
  test "yields a retained conversation" do
    conversation = create_conversation!

    yielded = Conversations::WithRetainedStateLock.call(
      conversation: conversation,
      record: conversation,
      message: "must be retained before publishing"
    ) do |current_conversation|
      current_conversation
    end

    assert_equal conversation.id, yielded.id
  end

  test "rejects pending delete conversations" do
    conversation = create_conversation!
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::WithRetainedStateLock.call(
        conversation: conversation,
        record: conversation,
        message: "must be retained before publishing"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before publishing"
  end

  private

  def create_conversation!
    context = create_workspace_context!
    Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
  end
end
