module ProviderExecution
  class ExecutePromptCompactionNode
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, request_preparation_exchange: nil)
      @workflow_node = workflow_node
      @request_preparation_exchange = request_preparation_exchange
    end

    def call
      current_node = WorkflowNode.find_by_public_id!(@workflow_node.public_id)
      return current_node if current_node.waiting?
      return current_node if current_node.terminal? || current_node.running?

      raise_invalid!(current_node, :node_type, "must be a prompt_compaction workflow node") unless current_node.node_type == "prompt_compaction"

      claim_running!(current_node)
      artifact_payload = execute_compaction(current_node)
      persist_artifact!(current_node, artifact_payload)

      Workflows::CompleteNode.call(
        workflow_node: current_node,
        event_payload: {
          "artifact_key" => artifact_key(current_node),
          "artifact_kind" => artifact_payload.fetch("artifact_kind", "prompt_compaction_context"),
          "source" => artifact_payload["source"],
        }.compact
      )
      Workflows::RefreshRunLifecycle.call(workflow_run: current_node.workflow_run)
      Workflows::DispatchRunnableNodes.call(workflow_run: current_node.workflow_run)
      current_node.reload
    rescue ProviderExecution::AgentRequestExchange::PendingResponse
      current_node.reload
    rescue StandardError => error
      failure_result = fail_node!(current_node || @workflow_node, error)
      raise if failure_result.terminal?

      failure_result.workflow_node
    end

    private

    def execute_compaction(current_node)
      case strategy_for(current_node)
      when "runtime_required"
        execute_via_runtime(current_node)
      when "runtime_first"
        execute_runtime_with_fallback(current_node)
      when "embedded_only"
        execute_via_embedded(current_node)
      else
        raise ArgumentError, "prompt_compaction policy does not allow execution"
      end
    end

    def execute_runtime_with_fallback(current_node)
      return execute_via_embedded(current_node) unless runtime_execution_supported?(current_node)

      execute_via_runtime(current_node)
    rescue ProviderExecution::AgentRequestExchange::ExchangeError => error
      execute_via_embedded(
        current_node,
        runtime_failure_code: error.respond_to?(:code) ? error.code : error.class.name,
        fallback_used: true
      )
    end

    def execute_via_runtime(current_node)
      raise ArgumentError, "prompt_compaction runtime execution is unavailable" unless runtime_execution_supported?(current_node)

      result = request_preparation_exchange(current_node).execute_prompt_compaction(
        payload: request_payload(current_node)
      )
      artifact = result.fetch("artifact").deep_stringify_keys
      artifact["fallback_used"] = false unless artifact.key?("fallback_used")
      artifact
    end

    def execute_via_embedded(current_node, runtime_failure_code: nil, fallback_used: false)
      EmbeddedFeatures::PromptCompaction::Invoke.call(
        request_payload: request_payload(current_node).fetch("prompt_compaction")
      ).merge(
        "runtime_failure_code" => runtime_failure_code,
        "fallback_used" => fallback_used
      ).compact
    end

    def request_payload(current_node)
      {
        "protocol_version" => "agent-runtime/2026-04-01",
        "request_kind" => "execute_prompt_compaction",
        "task" => {
          "workflow_run_id" => current_node.workflow_run.public_id,
          "workflow_node_id" => current_node.public_id,
          "conversation_id" => current_node.conversation.public_id,
          "turn_id" => current_node.turn.public_id,
          "kind" => "prompt_compaction",
        },
        "prompt_compaction" => prompt_compaction_payload(current_node),
        "provider_context" => current_node.workflow_run.execution_snapshot.provider_context,
        "runtime_context" => current_node.workflow_run.execution_snapshot.runtime_context.merge(
          "logical_work_id" => "prompt-compaction:#{current_node.public_id}",
          "attempt_no" => 1
        ),
      }
    end

    def prompt_compaction_payload(current_node)
      metadata = normalized_metadata(current_node)

      {
        "candidate_messages" => Array(metadata.fetch("candidate_messages", [])).map(&:deep_stringify_keys),
        "budget_hints" => metadata.fetch("budget_hints", {}),
        "guard_result" => metadata.fetch("guard_result", {}),
        "consultation" => metadata["consultation"],
        "consultation_reason" => metadata["consultation_reason"],
        "policy" => metadata.fetch("policy", {}),
        "capability" => metadata.fetch("capability", {}),
        "selected_input_message_id" => metadata["selected_input_message_id"],
        "tokenizer_hint" => current_node.workflow_run.execution_snapshot.model_context["tokenizer_hint"],
      }.compact
    end

    def persist_artifact!(workflow_node, artifact_payload)
      WorkflowArtifact.create!(
        installation: workflow_node.installation,
        workflow_run: workflow_node.workflow_run,
        workflow_node: workflow_node,
        artifact_key: artifact_key(workflow_node),
        artifact_kind: artifact_payload.fetch("artifact_kind", "prompt_compaction_context"),
        storage_mode: "json_document",
        payload: artifact_payload
      )
    end

    def artifact_key(workflow_node)
      normalized_metadata(workflow_node).fetch("artifact_key")
    end

    def normalized_metadata(workflow_node)
      workflow_node.metadata.is_a?(Hash) ? workflow_node.metadata.deep_stringify_keys : {}
    end

    def strategy_for(workflow_node)
      normalized_metadata(workflow_node).dig("policy", "strategy").presence || "runtime_first"
    end

    def runtime_execution_supported?(workflow_node)
      capability = normalized_metadata(workflow_node).fetch("capability", {})
      capability["available"] == true && capability["workflow_execution"] == "supported"
    end

    def request_preparation_exchange(workflow_node)
      @request_preparation_exchange ||= ProviderExecution::RequestPreparationExchange.new(
        agent_definition_version: workflow_node.turn.agent_definition_version
      )
    end

    def claim_running!(workflow_node)
      workflow_node.with_lock do
        workflow_node.reload
        return if workflow_node.running?
        raise_invalid!(workflow_node, :lifecycle_state, "must be pending or queued before prompt compaction execution") unless workflow_node.pending? || workflow_node.queued?

        workflow_node.update!(
          lifecycle_state: "running",
          started_at: workflow_node.started_at || Time.current,
          finished_at: nil
        )
        WorkflowNodeEvent.create!(
          installation: workflow_node.installation,
          workflow_run: workflow_node.workflow_run,
          workflow_node: workflow_node,
          ordinal: workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
          event_kind: "status",
          payload: { "state" => "running" }
        )
      end
    end

    def fail_node!(workflow_node, error)
      classification = ProviderExecution::FailureClassification.call(error: error)

      Workflows::BlockNodeForFailure.call(
        workflow_node: workflow_node,
        failure_category: classification.failure_category,
        failure_kind: classification.failure_kind,
        retry_strategy: classification.retry_strategy,
        max_auto_retries: classification.max_auto_retries,
        next_retry_at: classification.next_retry_at,
        last_error_summary: classification.last_error_summary,
        metadata: {
          "error_class" => error.class.name,
        }
      )
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
