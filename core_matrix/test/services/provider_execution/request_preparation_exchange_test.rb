require "test_helper"

class ProviderExecution::RequestPreparationExchangeTest < ActiveSupport::TestCase
  ExchangeDouble = Struct.new(:consult_requests, :execute_requests, keyword_init: true) do
    def consult_prompt_compaction(payload:)
      consult_requests << payload.deep_stringify_keys
      {
        "status" => "ok",
        "decision" => "compact",
        "diagnostics" => { "reason" => "soft_threshold" },
      }
    end

    def execute_prompt_compaction(payload:)
      execute_requests << payload.deep_stringify_keys
      {
        "status" => "ok",
        "artifact" => {
          "artifact_kind" => "prompt_compaction_context",
          "messages" => [{ "role" => "user", "content" => "Compacted input" }],
        },
      }
    end
  end

  test "delegates consultation requests through the dedicated request-preparation exchange" do
    context = build_agent_control_context!
    exchange_double = ExchangeDouble.new(consult_requests: [], execute_requests: [])
    payload = {
      "task" => {
        "conversation_id" => context.fetch(:conversation).public_id,
        "workflow_node_id" => context.fetch(:workflow_node).public_id,
        "turn_id" => context.fetch(:turn).public_id,
        "kind" => "turn_step",
      },
      "prompt_compaction" => {
        "consultation_reason" => "soft_threshold",
      },
    }

    result = ProviderExecution::RequestPreparationExchange.new(
      agent_definition_version: context.fetch(:agent_definition_version),
      agent_request_exchange: exchange_double
    ).consult_prompt_compaction(payload: payload)

    assert_equal "compact", result.fetch("decision")
    assert_equal "soft_threshold", exchange_double.consult_requests.first.dig("prompt_compaction", "consultation_reason")
  end

  test "delegates workflow execution requests through the dedicated request-preparation exchange" do
    context = build_agent_control_context!(workflow_node_type: "prompt_compaction")
    exchange_double = ExchangeDouble.new(consult_requests: [], execute_requests: [])
    payload = {
      "task" => {
        "conversation_id" => context.fetch(:conversation).public_id,
        "workflow_node_id" => context.fetch(:workflow_node).public_id,
        "turn_id" => context.fetch(:turn).public_id,
        "kind" => "prompt_compaction",
      },
      "prompt_compaction" => {
        "consultation_reason" => "hard_limit",
      },
    }

    result = ProviderExecution::RequestPreparationExchange.new(
      agent_definition_version: context.fetch(:agent_definition_version),
      agent_request_exchange: exchange_double
    ).execute_prompt_compaction(payload: payload)

    assert_equal "prompt_compaction_context", result.dig("artifact", "artifact_kind")
    assert_equal "hard_limit", exchange_double.execute_requests.first.dig("prompt_compaction", "consultation_reason")
  end
end
