module ProviderExecution
  class PersistTurnStepPromptCompactionYield
    Result = Struct.new(
      :workflow_run,
      :workflow_node,
      :prompt_compaction_node,
      :successor_node,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, prompt_compaction_result:)
      @workflow_node = workflow_node
      @prompt_compaction_result = prompt_compaction_result.deep_stringify_keys
      @workflow_run = workflow_node.workflow_run
    end

    def call
      result = nil

      ApplicationRecord.transaction do
        ProviderExecution::WithFreshExecutionStateLock.call(workflow_node: @workflow_node) do |current_node, current_workflow_run, _current_turn|
          Workflows::Mutate.call(
            workflow_run: current_workflow_run,
            nodes: yielded_nodes(current_node),
            edges: yielded_edges(current_node)
          )

          current_node.update!(
            lifecycle_state: "completed",
            started_at: current_node.started_at || Time.current,
            finished_at: Time.current
          )
          append_status_event!(current_node, current_workflow_run)
          append_yield_event!(current_node, current_workflow_run)

          prompt_compaction_node = current_workflow_run.reload.workflow_nodes.find_by!(node_key: prompt_compaction_node_key(current_node))
          successor_node = current_workflow_run.workflow_nodes.find_by!(node_key: successor_node_key(current_node))
          result = Result.new(
            workflow_run: current_workflow_run,
            workflow_node: current_node,
            prompt_compaction_node: prompt_compaction_node,
            successor_node: successor_node
          )
        end
      end

      Workflows::RefreshRunLifecycle.call(workflow_run: @workflow_run)
      Workflows::DispatchRunnableNodes.call(workflow_run: @workflow_run)
      result
    end

    private

    def yielded_nodes(current_node)
      [
        {
          node_key: prompt_compaction_node_key(current_node),
          node_type: "prompt_compaction",
          yielding_node_key: current_node.node_key,
          provider_round_index: current_round_index(current_node),
          prior_tool_node_keys: Array(current_node.prior_tool_node_keys),
          presentation_policy: "internal_only",
          decision_source: "system",
          metadata: prompt_compaction_metadata(current_node),
        },
        {
          node_key: successor_node_key(current_node),
          node_type: "turn_step",
          yielding_node_key: current_node.node_key,
          provider_round_index: current_round_index(current_node),
          prior_tool_node_keys: Array(current_node.prior_tool_node_keys),
          presentation_policy: "internal_only",
          decision_source: "system",
          metadata: successor_metadata(current_node),
        },
      ]
    end

    def yielded_edges(current_node)
      [
        {
          from_node_key: current_node.node_key,
          to_node_key: prompt_compaction_node_key(current_node),
        },
        {
          from_node_key: prompt_compaction_node_key(current_node),
          to_node_key: successor_node_key(current_node),
        },
      ]
    end

    def prompt_compaction_metadata(current_node)
      {
        "artifact_key" => prompt_compaction_artifact_key(current_node),
        "candidate_messages" => Array(@prompt_compaction_result["candidate_messages"]).map(&:deep_stringify_keys),
        "budget_hints" => @prompt_compaction_result.fetch("budget_hints", {}),
        "guard_result" => @prompt_compaction_result.fetch("guard_result", {}),
        "consultation" => @prompt_compaction_result["consultation"],
        "consultation_reason" => @prompt_compaction_result["consultation_reason"],
        "policy" => @prompt_compaction_result.fetch("policy", {}),
        "capability" => @prompt_compaction_result.fetch("capability", {}),
        "selected_input_message_id" => @prompt_compaction_result["selected_input_message_id"],
        "prompt_compaction_attempt_no" => next_prompt_compaction_attempt_no(current_node),
        "overflow_recovery_attempt_no" => next_overflow_recovery_attempt_no(current_node),
      }.compact
    end

    def successor_metadata(current_node)
      {
        "prompt_compaction_artifact_key" => prompt_compaction_artifact_key(current_node),
        "prompt_compaction_source_node_key" => prompt_compaction_node_key(current_node),
        "prompt_compaction_includes_prior_tool_results" => true,
        "prompt_compaction_attempt_no" => next_prompt_compaction_attempt_no(current_node),
        "overflow_recovery_attempt_no" => next_overflow_recovery_attempt_no(current_node),
      }
    end

    def prompt_compaction_node_key(current_node)
      "#{current_node.node_key}_prompt_compaction_#{yield_index(current_node)}"
    end

    def successor_node_key(current_node)
      "#{prompt_compaction_node_key(current_node)}_successor"
    end

    def prompt_compaction_artifact_key(current_node)
      "#{prompt_compaction_node_key(current_node)}:context"
    end

    def yield_index(current_node)
      @yield_index ||= current_node.workflow_run.workflow_nodes.where(
        yielding_workflow_node: current_node,
        node_type: "prompt_compaction"
      ).count + 1
    end

    def current_round_index(current_node)
      value = current_node.provider_round_index
      value.present? ? value.to_i : 1
    end

    def next_prompt_compaction_attempt_no(current_node)
      current_metadata(current_node).fetch("prompt_compaction_attempt_no", 0).to_i + 1
    end

    def next_overflow_recovery_attempt_no(current_node)
      base_attempt_no = current_metadata(current_node).fetch("overflow_recovery_attempt_no", 0).to_i
      return base_attempt_no unless @prompt_compaction_result["consultation_reason"] == "overflow_recovery"

      base_attempt_no + 1
    end

    def current_metadata(current_node)
      current_node.metadata.is_a?(Hash) ? current_node.metadata.deep_stringify_keys : {}
    end

    def append_status_event!(workflow_node, workflow_run)
      WorkflowNodeEvent.create!(
        installation: workflow_run.installation,
        workflow_run: workflow_run,
        workflow_node: workflow_node,
        ordinal: workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
        event_kind: "status",
        payload: { "state" => "completed" }
      )
    end

    def append_yield_event!(workflow_node, workflow_run)
      WorkflowNodeEvent.create!(
        installation: workflow_run.installation,
        workflow_run: workflow_run,
        workflow_node: workflow_node,
        ordinal: workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
        event_kind: "yield_requested",
        payload: {
          "accepted_node_keys" => [
            prompt_compaction_node_key(workflow_node),
            successor_node_key(workflow_node),
          ],
          "artifact_key" => prompt_compaction_artifact_key(workflow_node),
        }
      )
    end
  end
end
