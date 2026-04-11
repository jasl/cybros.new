module Workflows
  class CreateForTurn
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, root_node_key:, root_node_type:, decision_source:, metadata:, presentation_policy: "internal_only", selector_source: "conversation", selector: nil, initial_kind: nil, initial_payload: {}, origin_turn: nil, subagent_connection: nil, dispatch_deadline_at: 5.minutes.from_now, execution_hard_deadline_at: 10.minutes.from_now, assignment_priority: 1)
      @turn = turn
      @root_node_key = root_node_key
      @root_node_type = root_node_type
      @decision_source = decision_source
      @metadata = metadata
      @presentation_policy = presentation_policy
      @selector_source = selector_source
      @selector = selector
      @initial_kind = initial_kind
      @initial_payload = initial_payload.deep_stringify_keys
      @origin_turn = origin_turn
      @subagent_connection = subagent_connection
      @dispatch_deadline_at = dispatch_deadline_at
      @execution_hard_deadline_at = execution_hard_deadline_at
      @assignment_priority = assignment_priority
    end

    def call
      ApplicationRecord.transaction do
        resolved_model_selection_snapshot = Workflows::ResolveModelSelector.call(
          turn: @turn,
          selector_source: @selector_source,
          selector: @selector
        )
        @turn.update!(resolved_model_selection_snapshot: resolved_model_selection_snapshot)
        execution_snapshot = Workflows::BuildExecutionSnapshot.call(turn: @turn)
        @turn.update!(resolved_config_snapshot: @turn.resolved_config_snapshot)

        workflow_run = WorkflowRun.create!(
          installation: @turn.installation,
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
          lifecycle_state: "pending",
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
      return if @initial_kind.blank?

      agent_task_run = AgentTaskRun.create!(
        installation: @turn.installation,
        agent: @turn.agent_snapshot.agent,
        workflow_run: workflow_run,
        workflow_node: workflow_node,
        conversation: @turn.conversation,
        turn: @turn,
        kind: @initial_kind,
        lifecycle_state: "queued",
        logical_work_id: logical_work_id,
        attempt_no: 1,
        task_payload: @initial_payload,
        progress_payload: {},
        terminal_payload: {},
        origin_turn: @origin_turn,
        subagent_connection: @subagent_connection
      )

      AgentControl::CreateExecutionAssignment.call(
        agent_task_run: agent_task_run,
        payload: {
          "task_payload" => agent_task_run.task_payload,
        },
        dispatch_deadline_at: @dispatch_deadline_at,
        execution_hard_deadline_at: @execution_hard_deadline_at,
        priority: @assignment_priority
      )
    end

    def logical_work_id
      return "subagent-step:#{@subagent_connection.public_id}:#{@turn.public_id}" if @subagent_connection.present?

      "turn-step:#{@turn.public_id}"
    end
  end
end
