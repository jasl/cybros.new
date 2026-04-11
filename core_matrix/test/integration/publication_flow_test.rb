require "test_helper"

class PublicationFlowTest < ActionDispatch::IntegrationTest
  test "publication visibility access logging and live projection follow canonical conversation state" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    viewer = create_user!(installation: context[:installation])
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Share this conversation",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(turn, content: "Visible output")
    event = ConversationEvents::Project.call(
      conversation: conversation,
      turn: turn,
      event_kind: "runtime.notice",
      payload: { "state" => "shared" }
    )

    publication = Publications::PublishLive.call(
      conversation: conversation,
      actor: context[:user],
      visibility_mode: "internal_public"
    )

    internal_access = Publications::RecordAccess.call(
      publication: publication,
      viewer_user: viewer,
      request_metadata: { "user_agent" => "Browser" }
    )
    assert_equal viewer, internal_access.viewer_user

    assert_raises(ActiveRecord::RecordInvalid) do
      Publications::RecordAccess.call(publication: publication, request_metadata: { "user_agent" => "Anon" })
    end

    publication = Publications::PublishLive.call(
      conversation: conversation,
      actor: context[:user],
      visibility_mode: "external_public"
    )

    slug_access = Publications::RecordAccess.call(
      slug: publication.slug,
      request_metadata: { "ip" => "127.0.0.1" }
    )
    token_access = Publications::RecordAccess.call(
      access_token: publication.plaintext_access_token,
      request_metadata: { "ip" => "127.0.0.2" }
    )
    entries = Publications::LiveProjection.call(publication: publication)

    assert_nil slug_access.viewer_user
    assert_nil token_access.viewer_user
    assert_equal %w[message conversation_event message], entries.map(&:entry_type)
    assert_equal turn.selected_input_message, entries[0].record
    assert_equal event, entries[1].record
    assert_equal output, entries[2].record

    Publications::Revoke.call(publication: publication, actor: context[:user])

    assert_raises(ActiveRecord::RecordInvalid) do
      Publications::RecordAccess.call(slug: publication.slug, request_metadata: { "ip" => "127.0.0.3" })
    end

    assert_equal(
      %w[publication.enabled publication.visibility_changed publication.revoked],
      AuditLog.where(installation: context[:installation]).order(:created_at).pluck(:action).last(3)
    )
    assert_equal 3, PublicationAccessEvent.where(publication: publication).count
  end
end
