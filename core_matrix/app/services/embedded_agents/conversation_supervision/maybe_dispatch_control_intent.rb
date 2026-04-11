module EmbeddedAgents
  module ConversationSupervision
    class MaybeDispatchControlIntent
      Result = Struct.new(
        :handled,
        :request_kind,
        :request_payload,
        :conversation_control_request,
        :response_kind,
        :message,
        keyword_init: true
      ) do
        def handled?
          handled == true
        end
      end

      def self.call(...)
        new(...).call
      end

      def initialize(actor:, conversation_supervision_session:, question:)
        @actor = actor
        @conversation_supervision_session = conversation_supervision_session
        @question = question
      end

      def call
        classification = ClassifyControlIntent.call(question: @question)
        return Result.new(handled: false, request_kind: nil, request_payload: {}) unless classification.matched?

        request = ConversationControl::CreateRequest.call(
          actor: @actor,
          conversation_supervision_session: @conversation_supervision_session,
          request_kind: classification.request_kind,
          request_payload: classification.request_payload
        )

        result_for_request(classification:, request:)
      rescue ActiveRecord::RecordInvalid => error
        result_for_creation_error(classification:, error:)
      end

      private

      def result_for_request(classification:, request:)
        response_kind, message =
          case request.lifecycle_state
          when "completed", "dispatched", "acknowledged"
            ["control_dispatched", successful_dispatch_message(classification.request_kind, request.lifecycle_state)]
          when "rejected"
            ["control_rejected", rejected_dispatch_message(classification.request_kind, request)]
          when "failed"
            ["control_failed", failed_dispatch_message(classification.request_kind, request)]
          else
            ["control_failed", "I recognized a control request, but it did not settle into a supported dispatch state."]
          end

        Result.new(
          handled: true,
          request_kind: classification.request_kind,
          request_payload: classification.request_payload,
          conversation_control_request: request,
          response_kind: response_kind,
          message: message
        )
      end

      def result_for_creation_error(classification:, error:)
        message = error.record.errors.full_messages.to_sentence
        response_kind =
          if message.match?(/not allowed to control|not allowed to access/i)
            "control_denied"
          elsif message.match?(/control is not enabled/i)
            "control_unavailable"
          else
            "control_failed"
          end

        Result.new(
          handled: true,
          request_kind: classification.request_kind,
          request_payload: classification.request_payload,
          conversation_control_request: nil,
          response_kind: response_kind,
          message: message
        )
      end

      def successful_dispatch_message(request_kind, lifecycle_state)
        action =
          case request_kind
          when "request_turn_interrupt"
            "I requested that the current task stop"
          when "request_conversation_close"
            "I requested that this task be closed"
          when "request_subagent_close"
            "I requested that the active child task stop"
          when "resume_waiting_workflow"
            "I requested that the waiting workflow resume"
          when "retry_blocked_step"
            "I requested a retry for the blocked step"
          else
            "I requested the control action"
          end

        "#{action}. The control request is #{lifecycle_state}."
      end

      def rejected_dispatch_message(request_kind, request)
        reason = request.result_payload["rejection_reason"].to_s
        "I understood this as #{human_request_label(request_kind)}, but could not dispatch it: #{reason}."
      end

      def failed_dispatch_message(request_kind, request)
        reason = request.result_payload["failure_reason"].to_s
        "I understood this as #{human_request_label(request_kind)}, but it failed while dispatching: #{reason}."
      end

      def human_request_label(request_kind)
        case request_kind
        when "request_turn_interrupt"
          "a stop request"
        when "request_conversation_close"
          "a task-close request"
        when "request_subagent_close"
          "a child-stop request"
        when "resume_waiting_workflow"
          "a resume request"
        when "retry_blocked_step"
          "a retry request"
        else
          "a control request"
        end
      end
    end
  end
end
