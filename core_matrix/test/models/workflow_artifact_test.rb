require "test_helper"

class WorkflowArtifactTest < ActiveSupport::TestCase
  test "supports json document and attached file storage modes" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Artifact input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run)

    inline_artifact = WorkflowArtifact.new(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      artifact_key: "summary",
      artifact_kind: "terminal_summary",
      storage_mode: "json_document",
      payload: { "summary" => "done" }
    )
    file_artifact = WorkflowArtifact.new(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      artifact_key: "bundle",
      artifact_kind: "archive",
      storage_mode: "attached_file",
      payload: {}
    )
    file_artifact.file.attach(
      io: StringIO.new("artifact"),
      filename: "artifact.txt",
      content_type: "text/plain"
    )

    assert inline_artifact.valid?
    assert file_artifact.valid?

    missing_file_artifact = WorkflowArtifact.new(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      artifact_key: "missing",
      artifact_kind: "archive",
      storage_mode: "attached_file",
      payload: {}
    )

    assert_not missing_file_artifact.valid?
    assert_includes missing_file_artifact.errors[:file], "must be attached for attached_file storage mode"
  end

  test "captures redundant projection metadata for workflow proof and inspection reads" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Artifact input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(
      workflow_run: workflow_run,
      presentation_policy: "internal_only"
    )

    artifact = WorkflowArtifact.create!(
      installation: context[:installation],
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      artifact_key: "batch-1",
      artifact_kind: "intent_batch_manifest",
      storage_mode: "json_document",
      payload: { "batch_id" => "batch-1" }
    )

    assert_equal conversation.workspace, artifact.workspace
    assert_equal conversation, artifact.conversation
    assert_equal turn, artifact.turn
    assert_equal workflow_node.node_key, artifact.workflow_node_key
    assert_equal workflow_node.ordinal, artifact.workflow_node_ordinal
    assert_equal "internal_only", artifact.presentation_policy
  end
end
