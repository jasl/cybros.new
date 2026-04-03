require "test_helper"

class Fenix::Runtime::PayloadContextTest < ActiveSupport::TestCase
  test "normalizes shared payload context from the execution payload" do
    payload = runtime_assignment_payload.fetch("payload")

    context = Fenix::Runtime::PayloadContext.call(payload:)

    assert_equal payload.dig("task", "agent_task_run_id"), context.fetch("agent_task_run_id")
    assert_equal payload.dig("task", "workflow_run_id"), context.fetch("workflow_run_id")
    assert_equal payload.dig("task", "workflow_node_id"), context.fetch("workflow_node_id")
    assert_equal payload.dig("task", "conversation_id"), context.fetch("conversation_id")
    assert_equal payload.dig("task", "turn_id"), context.fetch("turn_id")
    assert_equal payload.dig("task", "kind"), context.fetch("kind")
    assert_equal payload.fetch("task_payload"), context.fetch("task_payload")
    assert_equal payload.dig("runtime_context", "logical_work_id"), context.fetch("logical_work_id")
    assert_equal payload.dig("runtime_context", "attempt_no"), context.fetch("attempt_no")
    assert_equal payload.dig("runtime_context", "runtime_plane"), context.fetch("runtime_plane")
    assert_equal payload.dig("runtime_context", "agent_program_version_id"),
      context.dig("runtime_identity", "agent_program_version_id")
    assert_equal payload.dig("conversation_projection", "messages"), context.fetch("context_messages")
    assert_equal payload.dig("conversation_projection", "context_imports"), context.fetch("context_imports")
    assert_equal payload.dig("conversation_projection", "prior_tool_results"), context.fetch("prior_tool_results")
    assert_equal payload.dig("provider_context", "budget_hints"), context.fetch("budget_hints")
    assert_equal payload.dig("provider_context", "provider_execution"), context.fetch("provider_execution")
    assert_equal payload.dig("provider_context", "model_context"), context.fetch("model_context")
    assert_equal payload.dig("capability_projection", "tool_surface").map { |entry| entry.fetch("tool_name") },
      context.dig("agent_context", "allowed_tool_names")
    assert_equal payload.dig("capability_projection", "profile_key"), context.dig("agent_context", "profile")
    assert_equal payload.dig("capability_projection", "is_subagent"), context.dig("agent_context", "is_subagent")
    assert context.dig("workspace_context", "workspace_root").present?
    assert context.dig("workspace_context", "env_overlay").is_a?(Hash)
    assert context.dig("workspace_context", "prompts").is_a?(Hash)
  end

  test "falls back to mailbox defaults when runtime context omits shared execution fields" do
    mailbox_item = runtime_assignment_payload
    mailbox_item["logical_work_id"] = "logical-work-from-mailbox"
    mailbox_item["attempt_no"] = 3
    mailbox_item["runtime_plane"] = "program"
    mailbox_item.fetch("payload")["runtime_context"] = {
      "agent_program_version_id" => "agent-program-version-public-id",
    }

    context = Fenix::Runtime::PayloadContext.call(
      payload: mailbox_item.fetch("payload"),
      defaults: mailbox_item.slice("logical_work_id", "attempt_no", "runtime_plane")
    )

    assert_equal "logical-work-from-mailbox", context.fetch("logical_work_id")
    assert_equal 3, context.fetch("attempt_no")
    assert_equal "program", context.fetch("runtime_plane")
  end
end
