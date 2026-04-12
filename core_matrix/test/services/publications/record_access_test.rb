require "test_helper"

class Publications::RecordAccessTest < ActiveSupport::TestCase
  test "internal public allows authenticated installation users and rejects anonymous access" do
    context = create_workspace_context!
    viewer = create_user!(installation: context[:installation])
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    publication = Publications::PublishLive.call(
      conversation: conversation,
      actor: context[:user],
      visibility_mode: "internal_public"
    )

    event = Publications::RecordAccess.call(
      publication: publication,
      viewer_user: viewer,
      request_metadata: { "user_agent" => "Browser" }
    )

    assert_equal publication, event.publication
    assert_equal viewer, event.viewer_user
    assert_equal "publication", event.access_via

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Publications::RecordAccess.call(publication: publication, request_metadata: { "user_agent" => "Anon" })
    end

    assert_includes error.record.errors[:viewer_user], "must exist for internal public access"
  end

  test "external public allows anonymous access through slug or token" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    publication = Publications::PublishLive.call(
      conversation: conversation,
      actor: context[:user],
      visibility_mode: "external_public"
    )

    via_slug = Publications::RecordAccess.call(
      slug: publication.slug,
      request_metadata: { "ip" => "127.0.0.1" }
    )
    via_token = Publications::RecordAccess.call(
      access_token: publication.plaintext_access_token,
      request_metadata: { "ip" => "127.0.0.2" }
    )

    assert_nil via_slug.viewer_user
    assert_nil via_token.viewer_user
    assert_equal %w[slug access_token], PublicationAccessEvent.order(:id).pluck(:access_via)
  end
end
