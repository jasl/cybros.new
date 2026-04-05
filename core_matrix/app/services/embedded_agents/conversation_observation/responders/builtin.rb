module EmbeddedAgents
  module ConversationObservation
    module Responders
      class Builtin
        def self.call(...)
          new(...).call
        end

        def initialize(conversation_observation_session:, conversation_observation_frame:, observation_bundle:, question:)
          @conversation_observation_session = conversation_observation_session
          @conversation_observation_frame = conversation_observation_frame
          @observation_bundle = observation_bundle
          @question = question
        end

        def call
          assessment = BuildAssessment.call(
            conversation_observation_frame: @conversation_observation_frame,
            observation_bundle: @observation_bundle
          )
          supervisor_status = BuildSupervisorStatus.call(
            conversation_observation_frame: @conversation_observation_frame,
            assessment: assessment,
            observation_bundle: @observation_bundle
          )

          @conversation_observation_frame.update!(assessment_payload: assessment)

          {
            "assessment" => assessment,
            "supervisor_status" => supervisor_status,
            "human_sidechat" => human_sidechat(assessment, supervisor_status),
            "responder_kind" => "builtin",
          }
        end

        private

        def human_sidechat(assessment, supervisor_status)
          BuildHumanSidechat.call(
            question: @question,
            assessment: assessment,
            supervisor_status: supervisor_status,
            observation_bundle: @observation_bundle,
            previous_supervisor_status: previous_supervisor_status
          )
        end

        def previous_supervisor_status
          previous_frame = @conversation_observation_session.conversation_observation_frames
            .where.not(id: @conversation_observation_frame.id)
            .where.not(assessment_payload: {})
            .order(:created_at, :id)
            .last

          assessment = previous_frame&.assessment_payload
          return {} unless previous_frame.present?
          return {} unless assessment.is_a?(Hash) && assessment.present?

          BuildSupervisorStatus.call(
            conversation_observation_frame: previous_frame,
            assessment: assessment,
            observation_bundle: previous_frame.bundle_snapshot
          )
        end
      end
    end
  end
end
