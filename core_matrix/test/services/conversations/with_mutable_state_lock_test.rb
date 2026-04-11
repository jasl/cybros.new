require "test_helper"

class Conversations::WithMutableStateLockTest < ActiveSupport::TestCase
  test "yields a live mutable conversation" do
    conversation = create_conversation!

    yielded = Conversations::WithMutableStateLock.call(
      conversation: conversation,
      retained_message: "must be retained before mutating",
      active_message: "must be active before mutating",
      closing_message: "must not mutate while close is in progress"
    ) do |current_conversation|
      current_conversation
    end

    assert_equal conversation.id, yielded.id
  end

  test "rechecks mutable state after acquiring the conversation lock" do
    conversation = create_conversation!
    request_deletion_during_lock!(conversation)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::WithMutableStateLock.call(
        conversation: conversation,
        retained_message: "must be retained before mutating",
        active_message: "must be active before mutating",
        closing_message: "must not mutate while close is in progress"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before mutating"
  end

  private

  def create_conversation!
    context = create_workspace_context!
    Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
  end

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
