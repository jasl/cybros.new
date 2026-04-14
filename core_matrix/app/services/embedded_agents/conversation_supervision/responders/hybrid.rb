module EmbeddedAgents
  module ConversationSupervision
    module Responders
      class Hybrid
        GENERIC_RESPONSE_PATTERNS = [
          /\ARight now the conversation is (?:running|waiting|blocked|queued|idle)\.?\z/i,
          /\bno active blocker in this snapshot\b/i,
          /\bdoes not include a matching conversation fact\b/i,
        ].freeze

        def self.call(...)
          new(...).call
        end

        def initialize(actor: nil, conversation_supervision_session:, conversation_supervision_snapshot:, question:, control_decision: nil)
          @actor = actor
          @conversation_supervision_session = conversation_supervision_session
          @conversation_supervision_snapshot = conversation_supervision_snapshot
          @question = question.to_s
          @control_decision = control_decision
        end

        def call
          builtin = Builtin.call(
            actor: @actor,
            conversation_supervision_session: @conversation_supervision_session,
            conversation_supervision_snapshot: @conversation_supervision_snapshot,
            question: @question,
            control_decision: @control_decision
          )
          return builtin if @control_decision&.handled?
          return builtin if builtin_confident?(builtin)

          SummaryModel.call(
            actor: @actor,
            conversation_supervision_session: @conversation_supervision_session,
            conversation_supervision_snapshot: @conversation_supervision_snapshot,
            question: @question,
            control_decision: @control_decision
          )
        end

        private

        def builtin_confident?(builtin_output)
          content = builtin_output.dig("human_sidechat", "content").to_s.squish
          return false if content.blank?
          return false if chinese_question? && ascii_only?(content)
          return false if GENERIC_RESPONSE_PATTERNS.any? { |pattern| content.match?(pattern) }
          return false if generic_current_turn_response?(content) && !concrete_progress_signal?(content)

          true
        end

        def generic_current_turn_response?(content)
          content.match?(/\bworking through the current turn\b/i)
        end

        def concrete_progress_signal?(content)
          content.match?(%r{/[[:alnum:]_.\-]+}) ||
            content.match?(/\b(?:shell command|process|child task|browser content|test-and-build|npm|vite|workspace|2048)\b/i) ||
            content.match?(/\b(?:most recently|latest concrete step|blocked|waiting|finished|running)\b/i)
        end

        def chinese_question?
          @question.match?(/\p{Han}/)
        end

        def ascii_only?(text)
          text.ascii_only?
        end
      end
    end
  end
end
