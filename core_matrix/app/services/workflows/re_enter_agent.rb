module Workflows
  class ReEnterAgent
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, predecessor_nodes:, resume_reason:, wait_context: {})
      @workflow_run = workflow_run
      @predecessor_nodes = Array(predecessor_nodes)
      @resume_reason = resume_reason.to_s
      @wait_context = wait_context.deep_stringify_keys
    end

    def call
      Workflows::WithMutableWorkflowContext.call(
        workflow_run: @workflow_run,
        retained_message: "must be retained before re-entering agent work",
        active_message: "must be active before re-entering agent work",
        closing_message: "must not re-enter agent work while close is in progress"
      ) do |conversation, workflow_run, turn|
        return workflow_run unless workflow_run.resume_policy == "re_enter_agent"

        successor = workflow_run.resume_metadata.fetch("successor", {})
        return workflow_run if successor.blank?
        raise_invalid!(workflow_run, :wait_state, "must be ready before re-entering agent work") if workflow_run.waiting?
        raise_invalid!(turn, :lifecycle_state, "must be active before re-entering agent work") unless turn.active?

        predecessor_nodes = resolve_predecessor_nodes(workflow_run)
        raise_invalid!(workflow_run, :resume_metadata, "must include predecessor nodes to re-enter agent work") if predecessor_nodes.empty?

        successor_node = find_or_create_successor_node!(
          workflow_run: workflow_run,
          successor: successor,
          predecessor_nodes: predecessor_nodes
        )
        return existing_task(successor_node, workflow_run) if existing_task(successor_node, workflow_run).present?

        refresh_execution_snapshot!(turn)

        agent_task_run = AgentTaskRun.create!(
          installation: workflow_run.installation,
          agent_program: turn.agent_program_version.agent_program,
          workflow_run: workflow_run,
          workflow_node: successor_node,
          conversation: workflow_run.conversation,
          turn: turn,
          kind: successor_task_kind(successor_node),
          lifecycle_state: "queued",
          logical_work_id: successor_logical_work_id(turn, successor_node),
          attempt_no: 1,
          task_payload: successor_task_payload(workflow_run, predecessor_nodes),
          progress_payload: {},
          terminal_payload: {}
        )

        AgentControl::CreateExecutionAssignment.call(
          agent_task_run: agent_task_run,
          payload: {
            "task_payload" => agent_task_run.task_payload,
          },
          dispatch_deadline_at: 5.minutes.from_now,
          execution_hard_deadline_at: 10.minutes.from_now
        )

        agent_task_run
      end
    end

    private

    def resolve_predecessor_nodes(workflow_run)
      node_ids = @predecessor_nodes.filter_map do |node|
        node.respond_to?(:id) ? node.id : workflow_run.workflow_nodes.find_by(node_key: node.to_s)&.id
      end

      workflow_run.workflow_nodes.where(id: node_ids).order(:ordinal).to_a
    end

    def find_or_create_successor_node!(workflow_run:, successor:, predecessor_nodes:)
      node_key = successor.fetch("node_key")
      existing = workflow_run.workflow_nodes.find_by(node_key: node_key)
      return existing if existing.present?

      Workflows::Mutate.call(
        workflow_run: workflow_run,
        nodes: [
          {
            node_key: node_key,
            node_type: successor.fetch("node_type"),
            decision_source: "system",
            metadata: successor_node_metadata(workflow_run, predecessor_nodes),
          },
        ],
        edges: predecessor_nodes.map do |node|
          {
            from_node_key: node.node_key,
            to_node_key: node_key,
          }
        end
      )

      workflow_run.reload.workflow_nodes.find_by!(node_key: node_key)
    end

    def successor_node_metadata(workflow_run, predecessor_nodes)
      yielding_node_public_id = yielding_node_public_id_for(workflow_run)

      {
        "resume_batch_id" => workflow_run.resume_batch_id,
        "resume_reason" => @resume_reason,
        "yielding_node_id" => yielding_node_public_id,
        "yielding_node_key" => workflow_run.resume_yielding_node_key,
        "predecessor_node_keys" => predecessor_nodes.map(&:node_key),
        "wait_context" => @wait_context.presence,
      }.compact
    end

    def refresh_execution_snapshot!(turn)
      Workflows::BuildExecutionSnapshot.call(turn: turn.reload)
    end

    def successor_task_kind(successor_node)
      case successor_node.node_type
      when "turn_step", "agent_task_run"
        "turn_step"
      else
        raise_invalid!(successor_node, :node_type, "must map to a supported successor agent task kind")
      end
    end

    def successor_logical_work_id(turn, successor_node)
      "turn-step:#{turn.public_id}:#{successor_node.public_id}"
    end

    def successor_task_payload(workflow_run, predecessor_nodes)
      yielding_node_public_id = yielding_node_public_id_for(workflow_run)

      {
        "resume_batch_id" => workflow_run.resume_batch_id,
        "resume_reason" => @resume_reason,
        "yielding_node_id" => yielding_node_public_id,
        "yielding_node_key" => workflow_run.resume_yielding_node_key,
        "predecessor_node_keys" => predecessor_nodes.map(&:node_key),
        "wait_context" => @wait_context.presence,
      }.compact
    end

    def existing_task(successor_node, workflow_run)
      AgentTaskRun.find_by(workflow_run: workflow_run, workflow_node: successor_node)
    end

    def yielding_node_public_id_for(workflow_run)
      workflow_run
        .workflow_nodes
        .find_by(node_key: workflow_run.resume_yielding_node_key)
        &.public_id
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
