module ProviderExecution
  class PersistTurnStepYield
    Result = Struct.new(
      :workflow_run,
      :workflow_node,
      :usage_event,
      :execution_profile_fact,
      :materialized_nodes,
      :barrier_artifacts,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, request_context:, provider_result:, provider_request_id:, messages_count:, duration_ms:, tool_batch_result:, round_bindings:)
      @workflow_node = workflow_node
      @request_context = ProviderRequestContext.wrap(request_context)
      @provider_result = provider_result
      @provider_request_id = provider_request_id
      @messages_count = messages_count
      @duration_ms = duration_ms
      @tool_batch_result = tool_batch_result.deep_stringify_keys
      @round_bindings = Array(round_bindings)
      @workflow_run = workflow_node.workflow_run
    end

    def call
      result = nil

      ApplicationRecord.transaction do
        ProviderExecution::WithFreshExecutionStateLock.call(workflow_node: @workflow_node) do |current_node, current_workflow_run, _current_turn|
          usage_event = record_usage!(current_workflow_run)
          profiling_fact = record_profiling_fact!(current_workflow_run)
          materialized_nodes = materialize_graph!(current_node, current_workflow_run)
          barrier_artifacts = persist_barrier_artifacts!(current_node, current_workflow_run)
          persist_manifest_artifact!(current_node, current_workflow_run)
          current_node.update!(
            lifecycle_state: "completed",
            started_at: current_node.started_at || Time.current,
            finished_at: Time.current
          )
          append_status_event!(
            workflow_node: current_node,
            workflow_run: current_workflow_run,
            state: "completed",
            provider_request_id: @provider_request_id,
            usage_event_id: usage_event.id,
            execution_profile_fact_id: profiling_fact.id
          )
          append_yield_event!(
            workflow_node: current_node,
            workflow_run: current_workflow_run,
            accepted_node_keys: materialized_nodes.map(&:node_key),
            barrier_artifact_keys: barrier_artifacts.map(&:artifact_key)
          )

          result = Result.new(
            workflow_run: current_workflow_run,
            workflow_node: current_node,
            usage_event: usage_event,
            execution_profile_fact: profiling_fact,
            materialized_nodes: materialized_nodes,
            barrier_artifacts: barrier_artifacts
          )
        end
      end

      Workflows::RefreshRunLifecycle.call(workflow_run: @workflow_run)
      Workflows::DispatchRunnableNodes.call(workflow_run: @workflow_run)
      result
    end

    private

    def stages
      @stages ||= @tool_batch_result.fetch("stages")
    end

    def record_usage!(workflow_run)
      usage = normalize_usage(@provider_result.usage)

      ProviderUsage::RecordEvent.call(
        installation: workflow_run.installation,
        user: workflow_run.workspace.user,
        workspace: workflow_run.workspace,
        conversation_id: workflow_run.conversation_id,
        turn_id: workflow_run.turn_id,
        workflow_node_key: @workflow_node.node_key,
        agent_program: workflow_run.turn.agent_program_version.agent_program,
        agent_program_version: workflow_run.turn.agent_program_version,
        provider_handle: @request_context.provider_handle,
        model_ref: @request_context.model_ref,
        operation_kind: "text_generation",
        input_tokens: usage["input_tokens"],
        output_tokens: usage["output_tokens"],
        latency_ms: @duration_ms,
        success: true,
        entitlement_window_key: workflow_run.turn.resolved_model_selection_snapshot["entitlement_key"]
      )
    end

    def record_profiling_fact!(workflow_run)
      usage = normalize_usage(@provider_result.usage)
      total_tokens = usage["total_tokens"] || usage["input_tokens"].to_i + usage["output_tokens"].to_i
      threshold = @request_context.advisory_hints["recommended_compaction_threshold"]

      ExecutionProfiling::RecordFact.call(
        installation: workflow_run.installation,
        user: workflow_run.workspace.user,
        workspace: workflow_run.workspace,
        conversation_id: workflow_run.conversation_id,
        turn_id: workflow_run.turn_id,
        workflow_node_key: @workflow_node.node_key,
        fact_kind: "provider_request",
        fact_key: @workflow_node.node_key,
        count_value: @messages_count,
        duration_ms: @duration_ms,
        success: true,
        metadata: {
          "provider_request_id" => @provider_request_id,
          "provider_handle" => @request_context.provider_handle,
          "model_ref" => @request_context.model_ref,
          "api_model" => @request_context.api_model,
          "wire_api" => @request_context.wire_api,
          "execution_settings" => @request_context.execution_settings,
          "hard_limits" => @request_context.hard_limits,
          "advisory_hints" => @request_context.advisory_hints,
          "usage_evaluation" => {
            "source" => "provider",
            "input_tokens" => usage["input_tokens"],
            "output_tokens" => usage["output_tokens"],
            "total_tokens" => total_tokens,
            "recommended_compaction_threshold" => threshold,
            "threshold_crossed" => threshold.present? && total_tokens >= threshold,
          }.compact,
        }
      )
    end

    def materialize_graph!(current_node, workflow_run)
      nodes = []
      edges = []
      predecessor_node_key = current_node.node_key

      stages.each do |stage|
        stage.fetch("tool_entries").each do |entry|
          nodes << {
            node_key: entry.fetch("tool_node_key"),
            node_type: "tool_call",
            intent_kind: "tool_call",
            stage_index: stage.fetch("stage_index"),
            stage_position: entry.fetch("stage_position"),
            yielding_node_key: current_node.node_key,
            presentation_policy: "internal_only",
            decision_source: "llm",
            metadata: {
              "batch_id" => @tool_batch_result.fetch("batch_id"),
              "provider_round_index" => @tool_batch_result.fetch("provider_round_index"),
              "tool_call" => entry.fetch("tool_call"),
              "source_tool_binding_id" => entry.fetch("source_tool_binding_id"),
            },
          }
          edges << {
            from_node_key: predecessor_node_key,
            to_node_key: entry.fetch("tool_node_key"),
          }
        end

        nodes << {
          node_key: stage.fetch("join_node_key"),
          node_type: "barrier_join",
          stage_index: stage.fetch("stage_index"),
          yielding_node_key: current_node.node_key,
          presentation_policy: "internal_only",
          decision_source: "system",
          metadata: {
            "batch_id" => @tool_batch_result.fetch("batch_id"),
            "dispatch_mode" => stage.fetch("dispatch_mode"),
            "completion_barrier" => stage.fetch("completion_barrier"),
          },
        }

        stage.fetch("tool_entries").each do |entry|
          edges << {
            from_node_key: entry.fetch("tool_node_key"),
            to_node_key: stage.fetch("join_node_key"),
          }
        end

        predecessor_node_key = stage.fetch("join_node_key")
      end

      nodes << {
        node_key: @tool_batch_result.fetch("successor").fetch("node_key"),
        node_type: "turn_step",
        yielding_node_key: current_node.node_key,
        presentation_policy: "internal_only",
        decision_source: "system",
        metadata: @tool_batch_result.fetch("successor").fetch("metadata"),
      }
      edges << {
        from_node_key: predecessor_node_key,
        to_node_key: @tool_batch_result.fetch("successor").fetch("node_key"),
      }

      Workflows::Mutate.call(
        workflow_run: workflow_run,
        nodes: nodes,
        edges: edges
      )

      workflow_nodes = workflow_run.reload.workflow_nodes.where(node_key: nodes.map { |entry| entry.fetch(:node_key) }).index_by(&:node_key)
      clone_tool_bindings!(workflow_nodes)
      nodes.map { |entry| workflow_nodes.fetch(entry.fetch(:node_key)) }
    end

    def clone_tool_bindings!(workflow_nodes)
      source_bindings = @round_bindings.index_by(&:id)

      stages.each do |stage|
        stage.fetch("tool_entries").each do |entry|
          source_binding = source_bindings.fetch(entry.fetch("source_tool_binding_id"))
          tool_node = workflow_nodes.fetch(entry.fetch("tool_node_key"))

          ToolBinding.find_or_create_by!(
            workflow_node: tool_node,
            tool_definition: source_binding.tool_definition
          ) do |binding|
            binding.installation = tool_node.installation
            binding.tool_implementation = source_binding.tool_implementation
            binding.binding_reason = source_binding.binding_reason
            binding.binding_payload = source_binding.binding_payload.merge(
              "source_workflow_node_id" => @workflow_node.public_id,
              "source_workflow_node_key" => @workflow_node.node_key,
              "source_tool_binding_id" => source_binding.public_id,
              "tool_call_id" => entry.dig("tool_call", "call_id")
            )
          end
        end
      end
    end

    def persist_manifest_artifact!(workflow_node, workflow_run)
      WorkflowArtifact.create!(
        installation: workflow_run.installation,
        workflow_run: workflow_run,
        workflow_node: workflow_node,
        artifact_key: @tool_batch_result.fetch("batch_id"),
        artifact_kind: "provider_tool_batch_manifest",
        storage_mode: "json_document",
        payload: @tool_batch_result
      )
    end

    def persist_barrier_artifacts!(workflow_node, workflow_run)
      stages.map do |stage|
        WorkflowArtifact.create!(
          installation: workflow_run.installation,
          workflow_run: workflow_run,
          workflow_node: workflow_node,
          artifact_key: "#{@tool_batch_result.fetch("batch_id")}:stage:#{stage.fetch("stage_index")}",
          artifact_kind: "intent_batch_barrier",
          storage_mode: "json_document",
          payload: {
            "batch_id" => @tool_batch_result.fetch("batch_id"),
            "stage" => stage.slice("stage_index", "dispatch_mode", "completion_barrier"),
            "accepted_intent_ids" => stage.fetch("tool_entries").map { |entry| entry.fetch("tool_node_key") },
            "rejected_intent_ids" => [],
          }
        )
      end
    end

    def normalize_usage(usage)
      payload = usage.is_a?(Hash) ? usage : {}

      {
        "input_tokens" => payload[:prompt_tokens] || payload["prompt_tokens"] || payload[:input_tokens] || payload["input_tokens"],
        "output_tokens" => payload[:completion_tokens] || payload["completion_tokens"] || payload[:output_tokens] || payload["output_tokens"],
        "total_tokens" => payload[:total_tokens] || payload["total_tokens"],
      }.compact
    end

    def append_status_event!(workflow_node:, workflow_run:, state:, **payload)
      workflow_node.with_lock do
        WorkflowNodeEvent.create!(
          installation: workflow_run.installation,
          workflow_run: workflow_run,
          workflow_node: workflow_node,
          ordinal: workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
          event_kind: "status",
          payload: payload.merge("state" => state)
        )
      end
    end

    def append_yield_event!(workflow_node:, workflow_run:, accepted_node_keys:, barrier_artifact_keys:)
      workflow_node.with_lock do
        WorkflowNodeEvent.create!(
          installation: workflow_run.installation,
          workflow_run: workflow_run,
          workflow_node: workflow_node,
          ordinal: workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
          event_kind: "yield_requested",
          payload: {
            "batch_id" => @tool_batch_result.fetch("batch_id"),
            "accepted_node_keys" => accepted_node_keys,
            "barrier_artifact_keys" => barrier_artifact_keys,
          }
        )
      end
    end
  end
end
