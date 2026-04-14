require "test_helper"

class ProviderExecution::ExecutePromptCompactionNodeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ExchangeDouble = Struct.new(:execute_requests, :response, :error, keyword_init: true) do
    def execute_prompt_compaction(payload:)
      execute_requests << payload.deep_stringify_keys
      raise error if error.present?

      response.deep_dup
    end
  end

  test "executes prompt compaction through the runtime path and persists the returned artifact" do
    context = build_prompt_compaction_context!(
      capability: {
        "available" => true,
        "workflow_execution" => "supported",
      },
      policy: {
        "strategy" => "runtime_first",
      }
    )
    exchange_double = ExchangeDouble.new(
      execute_requests: [],
      response: {
        "artifact" => {
          "artifact_kind" => "prompt_compaction_context",
          "source" => "runtime",
          "messages" => [
            { "role" => "system", "content" => "Compacted context" },
          ],
        },
      }
    )

    assert_enqueued_with(job: Workflows::ExecuteNodeJob, queue: "llm_dev") do
      ProviderExecution::ExecutePromptCompactionNode.call(
        workflow_node: context.fetch(:workflow_node),
        request_preparation_exchange: exchange_double
      )
    end

    artifact = context.fetch(:workflow_run).reload.workflow_artifacts.find_by!(
      artifact_key: "prompt_compaction_node:context",
      artifact_kind: "prompt_compaction_context"
    )
    successor = context.fetch(:workflow_run).workflow_nodes.find_by!(node_key: "after_prompt_compaction")

    assert_equal "completed", context.fetch(:workflow_node).reload.lifecycle_state
    assert_equal "runtime", artifact.payload.fetch("source")
    assert_equal false, artifact.payload.fetch("fallback_used")
    assert_equal "queued", successor.reload.lifecycle_state
    assert_equal 1, exchange_double.execute_requests.length
  end

  test "falls back to embedded execution and persists degradation diagnostics when runtime execution fails" do
    context = build_prompt_compaction_context!(
      capability: {
        "available" => true,
        "workflow_execution" => "supported",
      },
      policy: {
        "strategy" => "runtime_first",
      }
    )
    exchange_double = ExchangeDouble.new(
      execute_requests: [],
      response: {},
      error: ProviderExecution::AgentRequestExchange::TimeoutError.new(
        code: "mailbox_timeout",
        message: "timed out waiting for agent response",
        details: {},
        retryable: true
      )
    )

    ProviderExecution::ExecutePromptCompactionNode.call(
      workflow_node: context.fetch(:workflow_node),
      request_preparation_exchange: exchange_double
    )

    artifact = context.fetch(:workflow_run).reload.workflow_artifacts.find_by!(
      artifact_key: "prompt_compaction_node:context",
      artifact_kind: "prompt_compaction_context"
    )

    assert_equal "embedded", artifact.payload.fetch("source")
    assert_equal true, artifact.payload.fetch("fallback_used")
    assert_equal "mailbox_timeout", artifact.payload.fetch("runtime_failure_code")
    assert_equal 1, exchange_double.execute_requests.length
  end

  private

  def build_prompt_compaction_context!(capability:, policy:)
    context = build_agent_control_context!(
      workflow_node_key: "prompt_compaction_node",
      workflow_node_type: "prompt_compaction",
      workflow_node_metadata: {
        "artifact_key" => "prompt_compaction_node:context",
        "candidate_messages" => [
          { "role" => "system", "content" => "You are a coding agent." },
          { "role" => "user", "content" => "Earlier context that needs compaction" },
          { "role" => "user", "content" => "Newest input" },
        ],
        "budget_hints" => {
          "hard_input_token_limit" => 40,
          "recommended_compaction_threshold" => 20,
        },
        "guard_result" => {
          "decision" => "compact_required",
          "failure_scope" => "full_context",
        },
        "consultation_reason" => "hard_limit",
        "policy" => policy,
        "capability" => capability,
        "selected_input_message_id" => "msg-current",
      }
    )

    Workflows::Mutate.call(
      workflow_run: context.fetch(:workflow_run),
      nodes: [
        {
          node_key: "after_prompt_compaction",
          node_type: "turn_step",
          decision_source: "system",
          metadata: {
            "prompt_compaction_artifact_key" => "prompt_compaction_node:context",
            "prompt_compaction_source_node_key" => "prompt_compaction_node",
          },
        },
      ],
      edges: [
        { from_node_key: "prompt_compaction_node", to_node_key: "after_prompt_compaction" },
      ]
    )

    context.merge(
      workflow_run: context.fetch(:workflow_run).reload,
      workflow_node: context.fetch(:workflow_run).workflow_nodes.find_by!(node_key: "prompt_compaction_node")
    )
  end
end
