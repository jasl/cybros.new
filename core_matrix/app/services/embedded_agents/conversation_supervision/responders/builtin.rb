module EmbeddedAgents
  module ConversationSupervision
    module Responders
      class Builtin
        def self.call(...)
          new(...).call
        end

        def initialize(conversation_supervision_session:, conversation_supervision_snapshot:, question:)
          @conversation_supervision_session = conversation_supervision_session
          @conversation_supervision_snapshot = conversation_supervision_snapshot
          @question = question
        end

        def call
          machine_status = @conversation_supervision_snapshot.machine_status_payload

          {
            "machine_status" => machine_status,
            "human_sidechat" => BuildHumanSidechat.call(
              question: @question,
              conversation_supervision_session: @conversation_supervision_session,
              conversation_supervision_snapshot: @conversation_supervision_snapshot,
              machine_status: machine_status
            ),
            "responder_kind" => "builtin",
          }
        end
      end
    end
  end
end
