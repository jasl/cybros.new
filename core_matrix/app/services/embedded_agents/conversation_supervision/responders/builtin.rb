module EmbeddedAgents
  module ConversationSupervision
    module Responders
      class Builtin
        def self.call(...)
          new(...).call
        end

        def initialize(actor: nil, conversation_supervision_session:, conversation_supervision_snapshot:, question:, control_decision: nil)
          @actor = actor
          @conversation_supervision_session = conversation_supervision_session
          @conversation_supervision_snapshot = conversation_supervision_snapshot
          @question = question
          @control_decision = control_decision
        end

        def call
          machine_status = @conversation_supervision_snapshot.machine_status_payload

          {
            "machine_status" => machine_status,
            "human_sidechat" => human_sidechat(machine_status),
            "responder_kind" => "builtin",
          }
        end

        private

        def human_sidechat(machine_status)
          return build_control_sidechat(machine_status) if @control_decision&.handled?

          BuildHumanSidechat.call(
            question: @question,
            conversation_supervision_session: @conversation_supervision_session,
            conversation_supervision_snapshot: @conversation_supervision_snapshot,
            machine_status: machine_status
          )
        end

        def build_control_sidechat(machine_status)
          {
            "supervision_session_id" => @conversation_supervision_session.public_id,
            "supervision_snapshot_id" => @conversation_supervision_snapshot.public_id,
            "conversation_id" => @conversation_supervision_snapshot.target_conversation.public_id,
            "overall_state" => machine_status.fetch("overall_state"),
            "intent" => "control_request",
            "classified_intent" => @control_decision.request_kind,
            "response_kind" => @control_decision.response_kind,
            "dispatch_state" => @control_decision.conversation_control_request&.lifecycle_state || "not_dispatched",
            "conversation_control_request_id" => @control_decision.conversation_control_request&.public_id,
            "content" => @control_decision.message,
          }.compact
        end
      end
    end
  end
end
