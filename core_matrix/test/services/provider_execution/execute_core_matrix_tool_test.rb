require "test_helper"

class ProviderExecution::ExecuteCoreMatrixToolTest < ActiveSupport::TestCase
  setup do
    delete_all_table_rows!
  end

  test "updates conversation metadata and returns accepted fields" do
    context = build_governed_tool_context!(
      profile_policy: governed_profile_policy.deep_merge(
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
      profile_policy: governed_profile_policy.deep_merge(
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

  test "reports only actually accepted fields when another submitted field is rejected by metadata policy" do
    context = build_governed_tool_context!(
      profile_policy: governed_profile_policy.deep_merge(
        "main" => {
          "allowed_tool_names" => %w[exec_command compact_context subagent_spawn conversation_metadata_update],
        }
      )
    )
    workflow_node = context.fetch(:workflow_node)
    existing_title = workflow_node.conversation.title
    existing_title_source = workflow_node.conversation.title_source

    result = ProviderExecution::ExecuteCoreMatrixTool.call(
      workflow_node: workflow_node,
      tool_call: {
        "tool_name" => "conversation_metadata_update",
        "arguments" => {
          "title" => "workflow_run_id stale",
          "summary" => "Agent summary",
        },
      }
    )

    conversation = workflow_node.conversation.reload

    assert_equal conversation.public_id, result.fetch("conversation_id")
    assert_equal({ "summary" => "Agent summary" }, result.fetch("accepted"))
    assert_equal({ "title" => "contains internal metadata content" }, result.fetch("rejected"))
    assert_equal existing_title, conversation.title
    assert_equal existing_title_source, conversation.title_source
    assert_equal "Agent summary", conversation.summary
    assert_equal "agent", conversation.summary_source
  end

  test "passes model selector hints through subagent spawn requests" do
    context = build_governed_tool_context!(
      profile_policy: governed_profile_policy.deep_merge(
        "researcher" => {
          "label" => "Researcher",
          "description" => "Delegated research profile",
          "allowed_tool_names" => %w[subagent_send subagent_wait subagent_close subagent_list],
        }
      ),
      workspace_agent_settings_payload: {
        "interactive_profile_key" => "main",
        "enabled_subagent_profile_keys" => ["researcher"],
        "default_subagent_profile_key" => "researcher",
      }
    )
    prepare_workflow_execution_setup!(context)
    workflow_node = context.fetch(:workflow_node)

    result = ProviderExecution::ExecuteCoreMatrixTool.call(
      workflow_node: workflow_node,
      tool_call: {
        "tool_name" => "subagent_spawn",
        "arguments" => {
          "content" => "Investigate the failure",
          "scope" => "conversation",
          "profile_key" => "researcher",
          "model_selector_hint" => "role:planner",
        },
      }
    )

    session = SubagentConnection.find_by!(public_id: result.fetch("subagent_connection_id"))

    assert_equal "role:planner", result.fetch("model_selector_hint")
    assert_equal "role:planner", session.resolved_model_selector_hint
  end
end
