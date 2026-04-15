require "test_helper"

class Shared::PayloadContextTest < ActiveSupport::TestCase
  test "preserves explicit memory and skill contexts from the payload" do
    context = Shared::PayloadContext.call(
      payload: {
        "task" => {
          "workflow_node_id" => "workflow-node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "kind" => "turn_step",
        },
        "round_context" => {
          "messages" => [
            { "role" => "user", "content" => "Use the provided context before delivery." },
          ],
          "context_imports" => [],
        },
        "agent_context" => {
          "profile" => "main",
          "allowed_tool_names" => %w[compact_context],
        },
        "provider_context" => {},
        "runtime_context" => {
          "agent_definition_version_id" => "agent-definition-version-1",
        },
        "memory_context" => {
          "summary" => "Runtime memory summary",
        },
        "skill_context" => {
          "active_skill_names" => ["deploy-agent"],
          "active_skill_contents" => ["Use evidence-backed deploy steps."],
        },
      }
    )

    assert_equal "Runtime memory summary", context.dig("memory_context", "summary")
    assert_equal ["deploy-agent"], context.dig("skill_context", "active_skill_names")
    assert_includes context.dig("skill_context", "active_skill_contents", 0), "Use evidence-backed deploy steps."
  end

  test "preserves workspace agent context from the payload" do
    context = Shared::PayloadContext.call(
      payload: {
        "task" => {
          "workflow_node_id" => "workflow-node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "kind" => "turn_step",
        },
        "workspace_agent_context" => {
          "workspace_agent_id" => "workspace-agent-1",
          "global_instructions" => "Use concise Chinese.\n",
        },
      }
    )

    assert_equal "workspace-agent-1", context.dig("workspace_agent_context", "workspace_agent_id")
    assert_equal "Use concise Chinese.\n", context.dig("workspace_agent_context", "global_instructions")
    refute context.key?("workspace_context")
  end
end
