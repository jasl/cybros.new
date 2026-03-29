module HumanInteractions
  class SubmitForm
    def self.call(...)
      new(...).call
    end

    def initialize(human_form_request:, submission_payload:)
      @human_form_request = human_form_request
      @submission_payload = submission_payload
    end

    def call
      HumanInteractions::WithMutableRequestContext.call(request: @human_form_request) do |request, workflow_run, conversation|
        raise_invalid!(request, :base, "must be open before form submission") unless request.open?
        if request.expired?
          return time_out_request!(request, workflow_run)
        end

        merged_result = request.request_payload.fetch("defaults", {}).merge(@submission_payload)
        validate_required_fields!(request, merged_result)

        request.resolve!(
          resolution_kind: "submitted",
          result_payload: merged_result
        )
        wait_context = resume_workflow!(request, workflow_run)
        project_event!(request, "human_interaction.resolved")
        re_enter_agent!(workflow_run, request, wait_context)
        request
      end
    end

    private

    def validate_required_fields!(request, merged_result)
      required_fields = Array(request.request_payload.dig("input_schema", "required"))

      required_fields.each do |field|
        next if merged_result[field].present?

        raise_invalid!(request, :result_payload, "must include required field #{field}")
      end
    end

    def time_out_request!(request, workflow_run)
      request.time_out!
      wait_context = resume_workflow!(request, workflow_run)
      project_event!(request, "human_interaction.timed_out")
      re_enter_agent!(workflow_run, request, wait_context)
      request
    end

    def resume_workflow!(request, workflow_run)
      return unless request.blocking?
      return unless workflow_run.waiting?
      return unless workflow_run.blocking_resource_type == "HumanInteractionRequest"
      return unless workflow_run.blocking_resource_id == request.public_id

      wait_context = {
        "wait_reason_kind" => workflow_run.wait_reason_kind,
        "wait_reason_payload" => workflow_run.wait_reason_payload,
        "waiting_since_at" => workflow_run.waiting_since_at,
        "blocking_resource_type" => workflow_run.blocking_resource_type,
        "blocking_resource_id" => workflow_run.blocking_resource_id,
      }
      workflow_run.update!(Workflows::WaitState.ready_attributes)
      wait_context
    end

    def project_event!(request, event_kind)
      ConversationEvents::Project.call(
        conversation: request.conversation,
        turn: request.turn,
        source: request,
        event_kind: event_kind,
        stream_key: "human_interaction_request:#{request.id}",
        payload: {
          "request_id" => request.public_id,
          "request_type" => request.type,
          "lifecycle_state" => request.lifecycle_state,
          "resolution_kind" => request.resolution_kind,
          "result_payload" => request.result_payload,
        }
      )
    end

    def re_enter_agent!(workflow_run, request, wait_context)
      return if wait_context.blank?

      Workflows::ReEnterAgent.call(
        workflow_run: workflow_run,
        predecessor_nodes: [request.workflow_node],
        resume_reason: "human_interaction_resolved",
        wait_context: wait_context
      )
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
