require "test_helper"

class Publications::PublishLiveTest < ActiveSupport::TestCase
  test "allows publishing while close is in progress because publication only requires retained state" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    ConversationCloseOperation.create!(
      installation: conversation.installation,
      conversation: conversation,
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    publication = Publications::PublishLive.call(
      conversation: conversation,
      actor: context[:user],
      visibility_mode: "internal_public"
    )

    assert publication.internal_public?
    assert_equal conversation.id, publication.conversation_id
  end

  test "publishes a conversation live and records the enable audit row" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )

    publication = Publications::PublishLive.call(
      conversation: conversation,
      actor: context[:user],
      visibility_mode: "internal_public"
    )

    assert publication.internal_public?
    assert_equal conversation, publication.conversation
    assert_equal context[:user], publication.owner_user
    assert_not_nil publication.published_at
    assert_not_nil publication.slug
    assert publication.matches_access_token?(publication.plaintext_access_token)

    audit_log = AuditLog.find_by!(action: "publication.enabled")
    assert_equal publication, audit_log.subject
    assert_equal context[:user], audit_log.actor
    assert_equal "internal_public", audit_log.metadata["visibility_mode"]
  end

  test "reuses the publication row and audits visibility changes" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    publication = Publications::PublishLive.call(
      conversation: conversation,
      actor: context[:user],
      visibility_mode: "internal_public"
    )

    changed = Publications::PublishLive.call(
      conversation: conversation,
      actor: context[:user],
      visibility_mode: "external_public"
    )

    assert_equal publication.id, changed.id
    assert changed.external_public?
    assert_equal 1, Publication.where(conversation: conversation).count

    audit_log = AuditLog.find_by!(action: "publication.visibility_changed")
    assert_equal changed, audit_log.subject
    assert_equal "internal_public", audit_log.metadata["previous_visibility_mode"]
    assert_equal "external_public", audit_log.metadata["visibility_mode"]
  end

  test "rejects publishing a pending delete conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Publications::PublishLive.call(
        conversation: conversation,
        actor: context[:user],
        visibility_mode: "internal_public"
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before publishing"
  end

  test "rechecks retained state after acquiring the conversation lock" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    request_deletion_during_lock!(conversation)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Publications::PublishLive.call(
        conversation: conversation,
        actor: context[:user],
        visibility_mode: "internal_public"
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before publishing"
    assert_nil Publication.find_by(conversation: conversation)
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
