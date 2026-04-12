require "test_helper"

class PublicationAccessEventTest < ActiveSupport::TestCase
  test "allows anonymous access rows and enforces viewer installation integrity" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    publication = Publication.create!(
      installation: context[:installation],
      conversation: conversation,
      owner_user: context[:user],
      visibility_mode: "external_public",
      slug: "pub-123",
      access_token_digest: Publication.digest_access_token("secret-token"),
      published_at: Time.current
    )

    anonymous = PublicationAccessEvent.new(
      installation: context[:installation],
      publication: publication,
      access_via: "slug",
      accessed_at: Time.current,
      request_metadata: { "ip" => "127.0.0.1" }
    )
    outsider = User.new(
      installation_id: -1,
      identity: create_identity!(email: unique_email(prefix: "outsider")),
      role: "member",
      display_name: "Outsider",
      preferences: {}
    )
    invalid = PublicationAccessEvent.new(
      installation: context[:installation],
      publication: publication,
      viewer_user: outsider,
      access_via: "publication",
      accessed_at: Time.current,
      request_metadata: {}
    )

    assert anonymous.valid?
    assert_not invalid.valid?
    assert_includes invalid.errors[:viewer_user], "must belong to the same installation"
  end
end
