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

          @conversation_observation_frame.update!(assessment_payload: assessment)

          {
            "assessment" => assessment,
            "supervisor_status" => supervisor_status(assessment),
            "human_sidechat" => human_sidechat(assessment),
            "responder_kind" => "builtin",
          }
        end

        private

        def supervisor_status(assessment)
          {
            "observation_session_id" => assessment.fetch("observation_session_id"),
            "observation_frame_id" => assessment.fetch("observation_frame_id"),
            "conversation_id" => assessment.fetch("conversation_id"),
            "overall_state" => assessment.fetch("overall_state"),
            "current_activity" => assessment.fetch("current_activity"),
            "workflow_run_id" => assessment["workflow_run_id"],
            "workflow_node_id" => assessment["workflow_node_id"],
            "last_progress_at" => assessment["last_progress_at"],
            "stall_for_ms" => assessment.fetch("stall_for_ms"),
            "blocking_reason" => assessment["blocking_reason"],
            "recent_activity_items" => assessment.fetch("recent_activity_items"),
            "transcript_refs" => assessment.fetch("transcript_refs"),
            "proof_refs" => assessment.fetch("proof_refs"),
          }.compact
        end

        def human_sidechat(assessment)
          BuildHumanSidechat.call(
            question: @question,
            assessment: assessment,
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
          return {} unless assessment.is_a?(Hash) && assessment.present?

          supervisor_status(assessment)
        end
      end
    end
  end
end
