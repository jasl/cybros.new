module EmbeddedAgents
  module ConversationSupervision
    class Authority
      CONTROL_VERBS = %w[
        request_status_refresh
        request_turn_interrupt
        request_conversation_close
        send_guidance_to_active_agent
        send_guidance_to_subagent
        request_subagent_close
        retry_blocked_step
        resume_waiting_workflow
      ].freeze
      PUBLIC_ID_PATTERN = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

      attr_reader :actor, :conversation, :policy

      def self.call(...)
        new(...).call
      end

      def initialize(actor:, conversation: nil, conversation_id: nil, conversation_public_id: nil)
        @actor = actor
        @conversation = conversation
        @conversation_id = conversation_id
        @conversation_public_id = conversation_public_id
      end

      def call
        @conversation = resolve_conversation
        @access = AppSurface::Policies::ConversationSupervisionAccess.call(
          user: actor,
          conversation: @conversation
        )
        @policy = @access.policy
        self
      end

      def allowed?
        accessible?
      end

      def accessible?
        @access.read?
      end

      def supervision_enabled?
        @access.supervision_enabled?
      end

      def side_chat_enabled?
        @access.side_chat_enabled?
      end

      def detailed_progress_enabled?
        @access.detailed_progress_enabled?
      end

      def control_enabled?
        @access.control_enabled?
      end

      def available_control_verbs
        @access.available_control_verbs
      end

      private

      def resolve_conversation
        return @conversation if @conversation.present?
        return find_by_public_id(@conversation_public_id) if @conversation_public_id.present?

        if @conversation_id.present?
          raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "conversation_id must use public ids" if @conversation_id.is_a?(Integer)

          return find_by_public_id(@conversation_id)
        end

        raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "conversation_id must use public ids"
      end

      def find_by_public_id(public_id)
        raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "conversation_id must use public ids" unless public_id.is_a?(String)
        raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "conversation_id must use public ids" unless public_id.match?(PUBLIC_ID_PATTERN)

        Conversation.find_by_public_id!(public_id)
      rescue ActiveRecord::RecordNotFound
        raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "conversation_id must use public ids"
      end
    end
  end
end
