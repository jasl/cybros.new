require "test_helper"

class ProviderExecution::ExecuteCoreMatrixToolTest < ActiveSupport::TestCase
  setup do
    Installation.destroy_all
  end

  test "updates conversation metadata and returns accepted fields" do
    context = build_governed_tool_context!(
      profile_catalog: governed_profile_catalog.deep_merge(
        "main" => {
          "allowed_tool_names" => %w[exec_command compact_context subagent_spawn conversation_metadata_update],
        }
      )
    )
    workflow_node = context.fetch(:workflow_node)

    result = ProviderExecution::ExecuteCoreMatrixTool.call(
      workflow_node: workflow_node,
      tool_call: {
        "tool_name" => "conversation_metadata_update",
        "arguments" => {
          "title" => "Agent title",
          "summary" => "Agent summary",
        },
      }
    )

    conversation = workflow_node.conversation.reload

    assert_equal conversation.public_id, result.fetch("conversation_id")
    assert_equal(
      {
        "title" => "Agent title",
        "summary" => "Agent summary",
      },
      result.fetch("accepted")
    )
    refute result.key?("rejected")
    assert_equal "Agent title", conversation.title
    assert_equal "Agent summary", conversation.summary
    assert_equal "agent", conversation.title_source
    assert_equal "agent", conversation.summary_source
  end

  test "returns a structured rejection for locked metadata fields" do
    context = build_governed_tool_context!(
      profile_catalog: governed_profile_catalog.deep_merge(
        "main" => {
          "allowed_tool_names" => %w[exec_command compact_context subagent_spawn conversation_metadata_update],
        }
      )
    )
    workflow_node = context.fetch(:workflow_node)
    workflow_node.conversation.update!(
      title: "Pinned title",
      title_source: "user",
      title_lock_state: "user_locked"
    )

    result = ProviderExecution::ExecuteCoreMatrixTool.call(
      workflow_node: workflow_node,
      tool_call: {
        "tool_name" => "conversation_metadata_update",
        "arguments" => {
          "title" => "Agent title",
          "summary" => "Agent summary",
        },
      }
    )

    conversation = workflow_node.conversation.reload

    assert_equal conversation.public_id, result.fetch("conversation_id")
    assert_equal({ "summary" => "Agent summary" }, result.fetch("accepted"))
    assert_equal({ "title" => "is locked by user" }, result.fetch("rejected"))
    assert_equal "Pinned title", conversation.title
    assert_equal "Agent summary", conversation.summary
    assert_equal "user", conversation.title_source
    assert_equal "agent", conversation.summary_source
  end
end
