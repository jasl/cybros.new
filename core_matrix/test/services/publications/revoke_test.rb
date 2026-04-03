require "test_helper"

class Publications::RevokeTest < ActiveSupport::TestCase
  test "revokes a live publication and records the revoke audit row" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    publication = Publications::PublishLive.call(
      conversation: conversation,
      actor: context[:user],
      visibility_mode: "external_public"
    )

    revoked = Publications::Revoke.call(
      publication: publication,
      actor: context[:user]
    )

    assert revoked.disabled?
    assert_not_nil revoked.revoked_at
    assert_not revoked.active?

    audit_log = AuditLog.find_by!(action: "publication.revoked")
    assert_equal revoked, audit_log.subject
    assert_equal "external_public", audit_log.metadata["previous_visibility_mode"]
  end
end
