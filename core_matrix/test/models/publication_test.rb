require "test_helper"

class PublicationTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    publication = Publication.create!(
      installation: context[:installation],
      conversation: conversation,
      owner_user: context[:user],
      visibility_mode: "internal_public",
      slug: "pub-#{next_test_sequence}",
      access_token_digest: Publication.digest_access_token("secret-token-#{next_test_sequence}"),
      published_at: Time.current
    )

    assert publication.public_id.present?
    assert_equal publication, Publication.find_by_public_id!(publication.public_id)
  end

  test "supports visibility modes token matching and revocation state helpers" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    publication = Publication.new(
      installation: context[:installation],
      conversation: conversation,
      owner_user: context[:user],
      visibility_mode: "external_public",
      slug: "pub-123",
      access_token_digest: Publication.digest_access_token("secret-token"),
      published_at: Time.current
    )

    assert publication.valid?
    assert publication.external_public?
    assert publication.active?
    assert publication.matches_access_token?("secret-token")

    publication.assign_attributes(
      visibility_mode: "disabled",
      revoked_at: Time.current
    )

    assert publication.valid?
    assert publication.disabled?
    assert publication.revoked?
    assert_not publication.active?
  end
end
