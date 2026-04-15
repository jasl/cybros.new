module Workflows
  class HandleWaitTransitionRequest
    def self.call(...)
      new(...).call
    end

    def initialize(agent_task_run:, terminal_payload:, occurred_at: Time.current)
      @agent_task_run = agent_task_run
      @workflow_run = agent_task_run.workflow_run
      @yielding_node = agent_task_run.workflow_node
      @terminal_payload = terminal_payload.deep_stringify_keys
      @occurred_at = occurred_at
    end

    def call
      transition = @terminal_payload["wait_transition_requested"]
      return @workflow_run if transition.blank?

      batch_manifest = transition.fetch("batch_manifest")
      materialization = Workflows::IntentBatchMaterialization.call(
        workflow_run: @workflow_run,
        yielding_node: @yielding_node,
        batch_manifest: batch_manifest
      )

      last_stage_nodes = []

      stages(batch_manifest).each do |stage|
        stage_nodes = materialization.accepted_nodes.select { |node| node.stage_index == stage.fetch("stage_index") }
        next if stage_nodes.empty?

        last_stage_nodes = stage_nodes
        materialize_stage!(stage, stage_nodes, batch_id: batch_manifest.fetch("batch_id"))
        return @workflow_run.reload if @workflow_run.reload.waiting?
      end

      Workflows::ReEnterAgent.call(
        workflow_run: @workflow_run,
        predecessor_nodes: last_stage_nodes.presence || [@yielding_node],
        resume_reason: "yield_complete"
      )
    end

    private

    def stages(batch_manifest)
      Array(batch_manifest.fetch("stages")).map do |stage|
        stage.deep_stringify_keys
      end
    end

    def materialize_stage!(stage, stage_nodes, batch_id:)
      stage_nodes.select { |node| human_interaction_node?(node) }.each do |node|
        payload = node.intent_payload
        HumanInteractions::Request.call(
          request_type: payload.fetch("request_type"),
          workflow_node: node,
          blocking: payload.fetch("blocking", true),
          request_payload: payload.fetch("request_payload", {})
        )
      end
      return if @workflow_run.reload.waiting?

      spawned_sessions = stage_nodes.select { |node| subagent_spawn_node?(node) }.map do |node|
        payload = node.intent_payload
        result = SubagentConnections::Spawn.call(
          conversation: @workflow_run.conversation,
          origin_turn: @workflow_run.turn,
          content: payload.fetch("content"),
          scope: payload.fetch("scope", "conversation"),
          profile_key: payload["profile_key"],
          model_selector_hint: payload["model_selector_hint"],
          task_payload: payload.fetch("task_payload", {})
        )
        node.update!(
          spawned_subagent_connection: SubagentConnection.find_by!(public_id: result.fetch("subagent_connection_id"))
        )
        Workflows::CompleteNode.call(
          workflow_node: node,
          event_payload: {
            "subagent_connection_id" => result.fetch("subagent_connection_id"),
          }
        )
        node.spawned_subagent_connection
      end

      return unless stage.fetch("completion_barrier") == "wait_all"
      return if spawned_sessions.blank?

      barrier_artifact = @workflow_run.reload.workflow_artifacts.find_by!(
        artifact_kind: "intent_batch_barrier",
        artifact_key: "#{batch_id}:stage:#{stage.fetch("stage_index")}"
      )

      @workflow_run.reload.update!(
        Workflows::WaitState.cleared_detail_attributes.merge(
          wait_state: "waiting",
          wait_reason_kind: "subagent_barrier",
          wait_reason_payload: {},
          waiting_since_at: @occurred_at,
          blocking_resource_type: "SubagentBarrier",
          blocking_resource_id: barrier_artifact.artifact_key
        )
      )
    end

    def human_interaction_node?(node)
      node.intent_kind == "human_interaction_request" || node.node_type == "human_interaction"
    end

    def subagent_spawn_node?(node)
      node.intent_kind == "subagent_spawn" || node.node_type == "subagent_spawn"
    end
  end
end
