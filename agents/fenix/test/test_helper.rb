ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    private

    def runtime_assignment_payload(runtime_plane: "agent", mode: "deterministic_tool", context_messages: default_context_messages, budget_hints: {}, provider_execution: {}, model_context: {}, agent_context: default_agent_context)
      {
        "item_id" => "mailbox-item-#{SecureRandom.uuid}",
        "message_id" => "kernel-assignment-#{SecureRandom.uuid}",
        "logical_work_id" => "logical-work-#{SecureRandom.uuid}",
        "attempt_no" => 1,
        "runtime_plane" => runtime_plane,
        "payload" => {
          "agent_task_run_id" => "task-#{SecureRandom.uuid}",
          "workflow_run_id" => "workflow-#{SecureRandom.uuid}",
          "workflow_node_id" => "node-#{SecureRandom.uuid}",
          "conversation_id" => "conversation-#{SecureRandom.uuid}",
          "turn_id" => "turn-#{SecureRandom.uuid}",
          "task_kind" => "turn_step",
          "task_payload" => { "mode" => mode, "expression" => "2 + 2" },
          "context_messages" => context_messages,
          "budget_hints" => {
            "reserved_output_tokens" => 256,
            "advisory_compaction_threshold_tokens" => 120,
          }.merge(budget_hints),
          "agent_context" => agent_context,
          "provider_execution" => {
            "provider_handle" => "openai",
            "model_ref" => "gpt-4.1-mini",
          }.merge(provider_execution),
          "model_context" => {
            "likely_model" => "gpt-4.1-mini",
          }.merge(model_context),
        },
      }
    end

    def default_context_messages
      [
        { "role" => "system", "content" => "You are Fenix." },
        { "role" => "user", "content" => "Please calculate 2 + 2." },
      ]
    end

    def default_agent_context
      {
        "profile" => "main",
        "is_subagent" => false,
        "allowed_tool_names" => %w[compact_context estimate_messages estimate_tokens calculator subagent_spawn subagent_send subagent_wait subagent_close subagent_list],
      }
    end
  end
end
