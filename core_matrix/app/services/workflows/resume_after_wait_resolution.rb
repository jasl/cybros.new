module Workflows
  class ResumeAfterWaitResolution
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:)
      @workflow_run = workflow_run
    end

    def call
      Workflows::WithMutableWorkflowContext.call(
        workflow_run: @workflow_run,
        retained_message: "must be retained before resuming waited work",
        active_message: "must be active before resuming waited work",
        closing_message: "must not resume waited work while close is in progress"
      ) do |_conversation, workflow_run, _turn|
        return workflow_run unless workflow_run.waiting?

        wait_context = current_wait_context(workflow_run)
        snapshot = WorkflowWaitSnapshot.new(wait_context)
        return workflow_run unless snapshot.resolved_for?(workflow_run)

        predecessor_nodes = predecessor_nodes_for(workflow_run, snapshot)
        workflow_run.update!(Workflows::WaitState.ready_attributes)

        Workflows::ReEnterAgent.call(
          workflow_run: workflow_run,
          predecessor_nodes: predecessor_nodes,
          resume_reason: "wait_resolved",
          wait_context: wait_context
        )
      end
    end

    private

    def current_wait_context(workflow_run)
      {
        "wait_reason_kind" => workflow_run.wait_reason_kind,
        "wait_reason_payload" => workflow_run.wait_reason_payload,
        "waiting_since_at" => workflow_run.waiting_since_at,
        "blocking_resource_type" => workflow_run.blocking_resource_type,
        "blocking_resource_id" => workflow_run.blocking_resource_id,
      }.compact
    end

    def predecessor_nodes_for(workflow_run, snapshot)
      case snapshot.wait_reason_kind
      when "human_interaction"
        request = HumanInteractionRequest.find_by(
          workflow_run: workflow_run,
          public_id: snapshot.blocking_resource_id
        )
        Array(request&.workflow_node)
      when "subagent_barrier"
        session_ids = Array(snapshot.wait_reason_payload["subagent_session_ids"]).map(&:to_s)
        workflow_run.workflow_nodes.includes(:spawned_subagent_session).order(:ordinal).select do |node|
          session_ids.include?(node.spawned_subagent_session&.public_id)
        end
      else
        []
      end
    end
  end
end
