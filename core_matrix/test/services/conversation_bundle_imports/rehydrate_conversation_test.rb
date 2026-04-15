require "test_helper"

class ConversationBundleImportsRehydrateConversationTest < ActiveSupport::TestCase
  test "creates a new conversation with preserved message order timestamps and attachments" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First importable question",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_message_attachment!(
      message: first_turn.selected_input_message,
      filename: "question.txt",
      body: "first attachment"
    )
    output_message = attach_selected_output!(first_turn, content: "First importable answer")
    output_attachment = create_message_attachment!(
      message: output_message,
      filename: "game-2048-dist.zip",
      body: "zip-bytes"
    )
    output_attachment.file.blob.update!(
      metadata: output_attachment.file.blob.metadata.merge(
        "publication_role" => "primary_deliverable",
        "source_kind" => "runtime_generated"
      )
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second importable question",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(second_turn, content: "Second importable answer")
    bundle = ConversationExports::WriteZipBundle.call(conversation: conversation)
    request = ConversationBundleImportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      user: context[:user],
      lifecycle_state: "queued",
      request_payload: {
        "target_agent_definition_version_id" => context[:agent_definition_version].public_id,
        "target_workspace_agent_id" => context[:workspace_agent].public_id,
      }
    )
    request.upload_file.attach(
      io: StringIO.new(bundle.fetch("io").read),
      filename: bundle.fetch("filename"),
      content_type: bundle.fetch("content_type")
    )
    request.save!

    parsed_bundle = ConversationBundleImports::ParseUpload.call(request: request)
    ConversationBundleImports::ValidateManifest.call(parsed_bundle: parsed_bundle)

    imported_conversation = ConversationBundleImports::RehydrateConversation.call(
      request: request,
      parsed_bundle: parsed_bundle
    )

    assert_not_equal conversation.public_id, imported_conversation.public_id
    assert_equal context[:workspace], imported_conversation.workspace
    assert_equal parsed_bundle.fetch("conversation_payload").fetch("messages").map { |message| message.fetch("content") },
      imported_conversation.messages.order(:created_at, :id).map(&:content)
    assert_equal parsed_bundle.fetch("conversation_payload").fetch("messages").map { |message| message.fetch("created_at") },
      imported_conversation.messages.order(:created_at, :id).map { |message| message.created_at.iso8601(6) }
    assert_equal 2, MessageAttachment.where(conversation: imported_conversation).count
    imported_output_message = imported_conversation.messages.find_by!(content: "First importable answer")
    imported_output_attachment = imported_output_message.message_attachments.first
    assert_equal "primary_deliverable", imported_output_attachment.file.blob.metadata["publication_role"]
    assert_equal "runtime_generated", imported_output_attachment.file.blob.metadata["source_kind"]
    assert_equal imported_conversation.turns.order(:sequence).last, imported_conversation.latest_turn
    assert_nil imported_conversation.latest_active_turn
    assert_equal imported_conversation.messages.order(:created_at, :id).last, imported_conversation.latest_message
    assert imported_conversation.current_execution_epoch.present?
    assert_equal "ready", imported_conversation.execution_continuity_state
    assert_equal [imported_conversation.current_execution_epoch.id],
      imported_conversation.turns.order(:sequence).pluck(:execution_epoch_id).uniq
  ensure
    bundle&.fetch("io")&.close!
  end

  test "rehydrates without issuing full latest-anchor refresh queries" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Importable question",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Importable answer")
    bundle = ConversationExports::WriteZipBundle.call(conversation: conversation)
    request = ConversationBundleImportRequest.new(
      installation: context[:installation],
      workspace: context[:workspace],
      user: context[:user],
      lifecycle_state: "queued",
      request_payload: {
        "target_agent_definition_version_id" => context[:agent_definition_version].public_id,
        "target_workspace_agent_id" => context[:workspace_agent].public_id,
      }
    )
    request.upload_file.attach(
      io: StringIO.new(bundle.fetch("io").read),
      filename: bundle.fetch("filename"),
      content_type: bundle.fetch("content_type")
    )
    request.save!

    parsed_bundle = ConversationBundleImports::ParseUpload.call(request: request)
    ConversationBundleImports::ValidateManifest.call(parsed_bundle: parsed_bundle)

    imported_conversation = nil
    queries = capture_sql_queries do
      imported_conversation = ConversationBundleImports::RehydrateConversation.call(
        request: request,
        parsed_bundle: parsed_bundle
      )
    end

    assert_equal imported_conversation.turns.order(:sequence).last, imported_conversation.latest_turn
    assert_equal imported_conversation.messages.order(:created_at, :id).last, imported_conversation.latest_message
    refute queries.any? { |sql| sql.match?(/FROM "turns" WHERE "turns"\."conversation_id" = .* ORDER BY "turns"\."sequence" DESC, "turns"\."id" DESC LIMIT/m) }
    refute queries.any? { |sql| sql.match?(/FROM "turns" WHERE "turns"\."conversation_id" = .* AND "turns"\."lifecycle_state" = .* ORDER BY "turns"\."sequence" DESC, "turns"\."id" DESC LIMIT/m) }
    refute queries.any? { |sql| sql.match?(/FROM "workflow_runs" WHERE "workflow_runs"\."conversation_id" = .* AND "workflow_runs"\."lifecycle_state" = .* ORDER BY "workflow_runs"\."created_at" DESC, "workflow_runs"\."id" DESC LIMIT/m) }
    refute queries.any? { |sql| sql.match?(/FROM "messages" WHERE "messages"\."conversation_id" = .* ORDER BY "messages"\."created_at" DESC, "messages"\."id" DESC LIMIT/m) }
  ensure
    bundle&.fetch("io")&.close!
  end

  test "rehydrates onto the targeted workspace agent and uses its default runtime" do
    installation = create_installation!
    user = create_user!(installation: installation)
    agent_default_runtime = create_execution_runtime!(installation: installation, display_name: "Agent Default Runtime")
    mounted_runtime = create_execution_runtime!(installation: installation, display_name: "Mounted Runtime")
    create_execution_runtime_connection!(installation: installation, execution_runtime: agent_default_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: mounted_runtime)
    agent = create_agent!(installation: installation, default_execution_runtime: agent_default_runtime)
    agent_definition_version = create_agent_definition_version!(installation: installation, agent: agent)
    create_agent_connection!(
      installation: installation,
      agent: agent,
      agent_definition_version: agent_definition_version
    )
    workspace = create_workspace!(installation: installation, user: user, name: "Import Target Workspace")
    workspace_agent = create_workspace_agent!(
      installation: installation,
      workspace: workspace,
      agent: agent,
      default_execution_runtime: mounted_runtime
    )
    conversation = Conversations::CreateRoot.call(workspace_agent: workspace_agent)
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Importable question",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Importable answer")
    bundle = ConversationExports::WriteZipBundle.call(conversation: conversation)
    request = ConversationBundleImportRequest.new(
      installation: installation,
      workspace: workspace,
      user: user,
      lifecycle_state: "queued",
      request_payload: {
        "target_agent_definition_version_id" => agent_definition_version.public_id,
        "target_workspace_agent_id" => workspace_agent.public_id,
      }
    )
    request.upload_file.attach(
      io: StringIO.new(bundle.fetch("io").read),
      filename: bundle.fetch("filename"),
      content_type: bundle.fetch("content_type")
    )
    request.save!

    parsed_bundle = ConversationBundleImports::ParseUpload.call(request: request)
    ConversationBundleImports::ValidateManifest.call(parsed_bundle: parsed_bundle)

    imported_conversation = ConversationBundleImports::RehydrateConversation.call(
      request: request,
      parsed_bundle: parsed_bundle
    )

    assert_equal workspace_agent, imported_conversation.workspace_agent
    assert_equal [mounted_runtime.id], imported_conversation.turns.order(:sequence).pluck(:execution_runtime_id).uniq
  ensure
    bundle&.fetch("io")&.close!
  end

  test "fails when the targeted workspace agent has been revoked before rehydrate" do
    installation = create_installation!
    user = create_user!(installation: installation)
    original_runtime = create_execution_runtime!(installation: installation, display_name: "Original Runtime")
    replacement_runtime = create_execution_runtime!(installation: installation, display_name: "Replacement Runtime")
    create_execution_runtime_connection!(installation: installation, execution_runtime: original_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: replacement_runtime)
    agent = create_agent!(installation: installation, default_execution_runtime: original_runtime)
    agent_definition_version = create_agent_definition_version!(installation: installation, agent: agent)
    create_agent_connection!(
      installation: installation,
      agent: agent,
      agent_definition_version: agent_definition_version
    )
    workspace = create_workspace!(installation: installation, user: user, name: "Revoked Import Workspace")
    original_workspace_agent = create_workspace_agent!(
      installation: installation,
      workspace: workspace,
      agent: agent,
      default_execution_runtime: original_runtime
    )
    conversation = Conversations::CreateRoot.call(workspace_agent: original_workspace_agent)
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Importable question",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Importable answer")
    bundle = ConversationExports::WriteZipBundle.call(conversation: conversation)
    request = ConversationBundleImportRequest.new(
      installation: installation,
      workspace: workspace,
      user: user,
      lifecycle_state: "queued",
      request_payload: {
        "target_agent_definition_version_id" => agent_definition_version.public_id,
        "target_workspace_agent_id" => original_workspace_agent.public_id,
      }
    )
    request.upload_file.attach(
      io: StringIO.new(bundle.fetch("io").read),
      filename: bundle.fetch("filename"),
      content_type: bundle.fetch("content_type")
    )
    request.save!

    original_workspace_agent.update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "owner_revoked"
    )
    create_workspace_agent!(
      installation: installation,
      workspace: workspace,
      agent: agent,
      default_execution_runtime: replacement_runtime
    )

    parsed_bundle = ConversationBundleImports::ParseUpload.call(request: request)
    ConversationBundleImports::ValidateManifest.call(parsed_bundle: parsed_bundle)

    assert_raises(ActiveRecord::RecordNotFound) do
      ConversationBundleImports::RehydrateConversation.call(
        request: request,
        parsed_bundle: parsed_bundle
      )
    end
  ensure
    bundle&.fetch("io")&.close!
  end
end
