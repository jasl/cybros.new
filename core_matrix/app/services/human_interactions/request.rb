module HumanInteractions
  class Request
    include HumanInteractions::LockedContext

    REQUEST_TYPES = {
      "ApprovalRequest" => ApprovalRequest,
      "HumanFormRequest" => HumanFormRequest,
      "HumanTaskRequest" => HumanTaskRequest,
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(request_type:, workflow_node:, request_payload:, blocking: true, expires_at: nil)
      @request_type = request_type.to_s
      @workflow_node = workflow_node
      @request_payload = request_payload
      @blocking = blocking
      @expires_at = expires_at
    end

    def call
      klass = REQUEST_TYPES[@request_type]
      raise_invalid_type! if klass.blank?

      with_locked_workflow_context(@workflow_node.id) do |workflow_node, workflow_run, conversation|
        Conversations::ValidateMutableState.call(
          conversation: conversation,
          record: conversation,
          retained_message: "must be retained before opening human interaction",
          active_message: "must be active before opening human interaction",
          closing_message: "must not open human interaction while close is in progress"
        )
        if workflow_run.turn.cancellation_reason_kind == "turn_interrupted"
          raise_invalid!(workflow_run, :turn, "must not be fenced by turn interrupt")
        end
        raise_invalid!(workflow_run, :wait_state, "must be ready before opening another blocking human interaction") if @blocking && workflow_run.waiting?

        request = klass.create!(
          installation: workflow_node.installation,
          workflow_run: workflow_run,
          workflow_node: workflow_node,
          conversation: conversation,
          turn: workflow_run.turn,
          lifecycle_state: "open",
          blocking: @blocking,
          request_payload: @request_payload,
          result_payload: {},
          expires_at: @expires_at
        )

        wait_for_request!(workflow_run, request) if request.blocking?
        project_event!(request, "human_interaction.opened")
        request
      end
    end

    private

    def raise_invalid_type!
      request = HumanInteractionRequest.new(type: @request_type)
      request.errors.add(:type, "must be a supported human interaction request subtype")
      raise ActiveRecord::RecordInvalid, request
    end

    def wait_for_request!(workflow_run, request)
      workflow_run.update!(
        wait_state: "waiting",
        wait_reason_kind: "human_interaction",
        wait_reason_payload: {
          "request_id" => request.public_id,
          "request_type" => request.type,
        },
        waiting_since_at: Time.current,
        blocking_resource_type: "HumanInteractionRequest",
        blocking_resource_id: request.public_id
      )
    end

    def project_event!(request, event_kind)
      ConversationEvents::Project.call(
        conversation: request.conversation,
        turn: request.turn,
        source: request,
        event_kind: event_kind,
        stream_key: stream_key_for(request),
        payload: event_payload(request)
      )
    end

    def event_payload(request)
      {
        "request_id" => request.public_id,
        "request_type" => request.type,
        "lifecycle_state" => request.lifecycle_state,
        "blocking" => request.blocking,
        "request_payload" => request.request_payload,
      }.tap do |payload|
        payload["resolution_kind"] = request.resolution_kind if request.resolution_kind.present?
        payload["result_payload"] = request.result_payload if request.result_payload.present?
      end
    end

    def stream_key_for(request)
      "human_interaction_request:#{request.id}"
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
