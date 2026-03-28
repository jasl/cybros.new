module Workflows
  class CreateForTurn
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, root_node_key:, root_node_type:, decision_source:, metadata:, presentation_policy: "internal_only", selector_source: "conversation", selector: nil, initial_task_kind: nil, initial_task_payload: {}, requested_by_turn: nil, subagent_session: nil, dispatch_deadline_at: 5.minutes.from_now, execution_hard_deadline_at: 10.minutes.from_now, assignment_priority: 1)
      @turn = turn
      @root_node_key = root_node_key
      @root_node_type = root_node_type
      @decision_source = decision_source
      @metadata = metadata
      @presentation_policy = presentation_policy
      @selector_source = selector_source
      @selector = selector
      @initial_task_kind = initial_task_kind
      @initial_task_payload = initial_task_payload.deep_stringify_keys
      @requested_by_turn = requested_by_turn
      @subagent_session = subagent_session
      @dispatch_deadline_at = dispatch_deadline_at
      @execution_hard_deadline_at = execution_hard_deadline_at
      @assignment_priority = assignment_priority
    end

    def call
      ApplicationRecord.transaction do
        Conversations::RefreshRuntimeContract.call(conversation: @turn.conversation)
        resolved_model_selection_snapshot = Workflows::ResolveModelSelector.call(
          turn: @turn,
          selector_source: @selector_source,
          selector: @selector
        )
        @turn.update!(resolved_model_selection_snapshot: resolved_model_selection_snapshot)
        execution_snapshot = Workflows::BuildExecutionSnapshot.call(turn: @turn)
        @turn.update!(
          resolved_config_snapshot: @turn.resolved_config_snapshot,
          execution_snapshot_payload: execution_snapshot.to_h
        )

        workflow_run = WorkflowRun.create!(
          installation: @turn.installation,
          workspace: @turn.conversation.workspace,
          conversation: @turn.conversation,
          turn: @turn,
          lifecycle_state: "active"
        )

        workflow_node = WorkflowNode.create!(
          installation: workflow_run.installation,
          workflow_run: workflow_run,
          ordinal: 0,
          node_key: @root_node_key,
          node_type: @root_node_type,
          presentation_policy: @presentation_policy,
          decision_source: @decision_source,
          metadata: @metadata
        )

        create_initial_task_run!(workflow_run: workflow_run, workflow_node: workflow_node, execution_snapshot: execution_snapshot)

        workflow_run
      end
    end

    private

    def create_initial_task_run!(workflow_run:, workflow_node:, execution_snapshot:)
      return if @initial_task_kind.blank?

      agent_task_run = AgentTaskRun.create!(
        installation: @turn.installation,
        agent_installation: @turn.agent_deployment.agent_installation,
        workflow_run: workflow_run,
        workflow_node: workflow_node,
        conversation: @turn.conversation,
        turn: @turn,
        task_kind: @initial_task_kind,
        lifecycle_state: "queued",
        logical_work_id: logical_work_id,
        attempt_no: 1,
        task_payload: @initial_task_payload,
        progress_payload: {},
        terminal_payload: {},
        requested_by_turn: @requested_by_turn,
        subagent_session: @subagent_session
      )

      AgentControl::CreateExecutionAssignment.call(
        agent_task_run: agent_task_run,
        payload: {
          "task_payload" => agent_task_run.task_payload,
          "context_messages" => execution_snapshot.context_messages,
          "budget_hints" => execution_snapshot.budget_hints,
          "provider_execution" => execution_snapshot.provider_execution,
          "model_context" => execution_snapshot.model_context,
        },
        dispatch_deadline_at: @dispatch_deadline_at,
        execution_hard_deadline_at: @execution_hard_deadline_at,
        priority: @assignment_priority
      )
    end

    def logical_work_id
      return "subagent-step:#{@subagent_session.public_id}:#{@turn.public_id}" if @subagent_session.present?

      "turn-step:#{@turn.public_id}"
    end
  end
end
