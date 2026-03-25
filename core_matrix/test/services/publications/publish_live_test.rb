require "test_helper"

class Publications::PublishLiveTest < ActiveSupport::TestCase
  test "publishes a conversation live and records the enable audit row" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

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
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
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
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
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
end
