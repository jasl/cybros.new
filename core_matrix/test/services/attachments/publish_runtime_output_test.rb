require "test_helper"

class Attachments::PublishRuntimeOutputTest < ActiveSupport::TestCase
  test "publishes runtime-generated files onto the selected output message" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Publish the built output",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output_message = attach_selected_output!(turn, content: "Built output ready")
    turn.update!(lifecycle_state: "completed")

    Tempfile.create(["runtime-output", ".zip"]) do |file|
      file.binmode
      file.write("zip-bytes")
      file.rewind

      attachments = Attachments::PublishRuntimeOutput.call(
        turn: turn,
        files: [
          {
            path: file.path,
            filename: "game-2048-dist.zip",
            content_type: "application/zip",
          },
        ],
        publication_role: "primary_deliverable"
      )

      attachment = attachments.fetch(0)

      assert_equal output_message, attachment.message
      assert_equal "primary_deliverable", attachment.file.blob.metadata["publication_role"]
      assert_equal "runtime_generated", attachment.file.blob.metadata["source_kind"]
      assert_equal "game-2048-dist.zip", attachment.file.filename.to_s
    end
  end

  test "rejects runtime publication when the selected output message is missing" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Publish the built output",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    Tempfile.create(["runtime-output", ".zip"]) do |file|
      file.binmode
      file.write("zip-bytes")
      file.rewind

      error = assert_raises(Attachments::PublishRuntimeOutput::InvalidParameters) do
        Attachments::PublishRuntimeOutput.call(
          turn: turn,
          files: [
            {
              path: file.path,
              filename: "game-2048-dist.zip",
              content_type: "application/zip",
            },
          ],
          publication_role: "primary_deliverable"
        )
      end

      assert_equal "selected_output_message_missing", error.reason
    end
  end

  test "rejects runtime publication when the turn is not completed" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Publish the built output",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Built output ready")

    Tempfile.create(["runtime-output", ".zip"]) do |file|
      file.binmode
      file.write("zip-bytes")
      file.rewind

      error = assert_raises(Attachments::PublishRuntimeOutput::InvalidParameters) do
        Attachments::PublishRuntimeOutput.call(
          turn: turn,
          files: [
            {
              path: file.path,
              filename: "game-2048-dist.zip",
              content_type: "application/zip",
            },
          ],
          publication_role: "primary_deliverable"
        )
      end

      assert_equal "turn_not_completed", error.reason
    end
  end

  test "rejects runtime publication when publication_role is missing" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Publish the built output",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Built output ready")
    turn.update!(lifecycle_state: "completed")

    Tempfile.create(["runtime-output", ".zip"]) do |file|
      file.binmode
      file.write("zip-bytes")
      file.rewind

      error = assert_raises(Attachments::PublishRuntimeOutput::InvalidParameters) do
        Attachments::PublishRuntimeOutput.call(
          turn: turn,
          files: [
            {
              path: file.path,
              filename: "game-2048-dist.zip",
              content_type: "application/zip",
            },
          ]
        )
      end

      assert_equal "publication_role_required", error.reason
    end
  end

  test "rejects runtime publication when no files are provided" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Publish the built output",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Built output ready")
    turn.update!(lifecycle_state: "completed")

    error = assert_raises(Attachments::PublishRuntimeOutput::InvalidParameters) do
      Attachments::PublishRuntimeOutput.call(
        turn: turn,
        files: [],
        publication_role: "primary_deliverable"
      )
    end

    assert_equal "files_missing", error.reason
  end

  test "rejects runtime publication when artifact ingress is disabled" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    conversation.update!(
      entry_policy_payload: conversation.entry_policy_snapshot.merge("artifact_ingress" => false)
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Publish the built output",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Built output ready")
    turn.update!(lifecycle_state: "completed")

    Tempfile.create(["runtime-output", ".zip"]) do |file|
      file.binmode
      file.write("zip-bytes")
      file.rewind

      error = assert_raises(Attachments::PublishRuntimeOutput::InvalidParameters) do
        Attachments::PublishRuntimeOutput.call(
          turn: turn,
          files: [
            {
              path: file.path,
              filename: "game-2048-dist.zip",
              content_type: "application/zip",
            },
          ],
          publication_role: "primary_deliverable"
        )
      end

      assert_equal "artifact_ingress_not_allowed", error.reason
    end
  end
end
