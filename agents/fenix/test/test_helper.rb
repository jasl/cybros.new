ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "json"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    private

    def shared_contract_fixture(name)
      ::JSON.parse(
        File.read(Rails.root.join("..", "..", "contracts", "#{name}.json"))
      )
    end

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
            "hard_limits" => {
              "context_window_tokens" => 1_000_000,
              "max_output_tokens" => 128_000,
            },
            "advisory_hints" => {
              "recommended_compaction_threshold" => 120,
            },
          }.deep_merge(budget_hints),
          "agent_context" => agent_context,
          "provider_execution" => {
            "wire_api" => "responses",
            "execution_settings" => {
              "temperature" => 0.2,
            },
          }.merge(provider_execution),
          "model_context" => {
            "provider_handle" => "openai",
            "model_ref" => "gpt-4.1-mini",
            "api_model" => "gpt-4.1-mini",
            "wire_api" => "responses",
            "transport" => "http",
            "tokenizer_hint" => "o200k_base",
            "provider_metadata" => {},
            "model_metadata" => {},
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
        "owner_conversation_id" => "owner-conversation-#{SecureRandom.uuid}",
        "allowed_tool_names" => %w[compact_context estimate_messages estimate_tokens calculator subagent_spawn subagent_send subagent_wait subagent_close subagent_list],
      }
    end
  end
end
