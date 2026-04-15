module IngressCommands
  class Dispatch
    REPORT_QUESTION = "What are you doing right now, what changed most recently, what are the blockers, and what will you do next?".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(command:, context:)
      @command = command
      @context = context
    end

    def call
      case @command.name
      when "stop"
        dispatch_stop
      when "report"
        dispatch_sidecar_query(command_name: "report", question: REPORT_QUESTION)
      when "btw"
        dispatch_sidecar_query(command_name: "btw", question: @command.arguments)
      when "regenerate"
        IngressAPI::Result.handled(
          handled_via: "transcript_command",
          trace: @context.pipeline_trace,
          envelope: @context.envelope,
          conversation: @context.conversation,
          channel_session: @context.channel_session,
          command_name: "regenerate",
          request_metadata: @context.request_metadata
        )
      else
        IngressAPI::Result.rejected(
          rejection_reason: "unsupported_command",
          trace: @context.pipeline_trace,
          envelope: @context.envelope,
          conversation: @context.conversation,
          channel_session: @context.channel_session,
          command_name: @command.name,
          request_metadata: @context.request_metadata
        )
      end
    end

    private

    def dispatch_stop
      active_turn = @context.active_turn || @context.conversation&.latest_active_turn
      Conversations::RequestTurnInterrupt.call(turn: active_turn) if active_turn.present?

      IngressAPI::Result.handled(
        handled_via: "control",
        trace: @context.pipeline_trace,
        envelope: @context.envelope,
        conversation: @context.conversation,
        channel_session: @context.channel_session,
        command_name: "stop",
        request_metadata: @context.request_metadata
      )
    end

    def dispatch_sidecar_query(command_name:, question:)
      payload = sidecar_response_payload(question:)

      IngressAPI::Result.handled(
        handled_via: "sidecar_query",
        trace: @context.pipeline_trace,
        envelope: @context.envelope,
        conversation: @context.conversation,
        channel_session: @context.channel_session,
        command_name: command_name,
        request_metadata: @context.request_metadata,
        payload: payload
      )
    rescue EmbeddedAgents::Errors::UnauthorizedSupervision
      IngressAPI::Result.rejected(
        rejection_reason: "sidecar_query_not_allowed",
        trace: @context.pipeline_trace,
        envelope: @context.envelope,
        conversation: @context.conversation,
        channel_session: @context.channel_session,
        command_name: command_name,
        request_metadata: @context.request_metadata
      )
    end

    def sidecar_response_payload(question:)
      actor = @context.conversation&.user
      conversation = @context.conversation
      raise EmbeddedAgents::Errors::UnauthorizedSupervision, "sidecar query actor is unavailable" if actor.blank? || conversation.blank?

      supervision_access = AppSurface::Policies::ConversationSupervisionAccess.call(
        user: actor,
        conversation: conversation
      )
      session = EmbeddedAgents::ConversationSupervision::CreateSession.call(
        actor: actor,
        conversation: conversation,
        responder_strategy: "builtin",
        supervision_access: supervision_access
      )
      snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
        actor: actor,
        conversation_supervision_session: session,
        supervision_access: supervision_access
      )
      response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
        actor: actor,
        conversation_supervision_session: session,
        conversation_supervision_snapshot: snapshot,
        question: question
      )

      {
        "question" => question,
        "machine_status" => response.fetch("machine_status"),
        "human_sidechat" => response.fetch("human_sidechat"),
        "responder_kind" => response.fetch("responder_kind"),
      }
    ensure
      if actor.present? && session.present?
        EmbeddedAgents::ConversationSupervision::CloseSession.call(
          actor: actor,
          conversation_supervision_session: session,
          supervision_access: supervision_access
        )
      end
    end
  end
end
