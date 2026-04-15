module IngressAPI
  module Preprocessors
    class AuthorizeAndPair
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        @context.append_trace("authorize_and_pair")
        return @context unless @context.envelope.peer_kind == "dm"
        return @context if @context.channel_session.present?

        pairing_request = latest_pairing_request
        if pairing_request&.approved?
          @context.channel_session = ensure_dm_session!(pairing_request)
          return @context
        end

        pairing_request = pairing_request if pairing_request&.pending?
        pairing_request ||= create_pairing_request!

        @context.result = IngressAPI::Result.handled(
          handled_via: "pairing_required",
          trace: @context.pipeline_trace,
          envelope: @context.envelope,
          conversation: nil,
          channel_session: nil,
          request_metadata: @context.request_metadata,
          payload: {
            "pairing_request_id" => pairing_request.public_id
          }
        )
        @context
      end

      private

      def latest_pairing_request
        ChannelPairingRequest.where(
          installation_id: @context.ingress_binding.installation_id,
          ingress_binding_id: @context.ingress_binding.id,
          channel_connector_id: @context.channel_connector.id,
          platform_sender_id: @context.envelope.external_sender_id
        ).order(created_at: :desc).first
      end

      def create_pairing_request!
        _plaintext_code, digest = ChannelPairingRequest.issue_pairing_code

        ChannelPairingRequest.create!(
          installation: @context.ingress_binding.installation,
          ingress_binding: @context.ingress_binding,
          channel_connector: @context.channel_connector,
          platform_sender_id: @context.envelope.external_sender_id,
          sender_snapshot: @context.envelope.sender_snapshot,
          pairing_code_digest: digest,
          lifecycle_state: "pending",
          expires_at: 30.minutes.from_now
        )
      end

      def ensure_dm_session!(pairing_request)
        ChannelSession.transaction do
          existing_session = existing_dm_session
          return bind_pairing_request!(pairing_request, existing_session) if existing_session.present?

          conversation = Conversations::CreateRoot.call(
            workspace_agent: @context.ingress_binding.workspace_agent,
            execution_runtime: resolved_execution_runtime
          )
          session = ChannelSession.create!(
            installation: @context.ingress_binding.installation,
            ingress_binding: @context.ingress_binding,
            channel_connector: @context.channel_connector,
            conversation: conversation,
            platform: @context.channel_connector.platform,
            peer_kind: "dm",
            peer_id: @context.envelope.external_sender_id,
            thread_key: nil,
            binding_state: "active",
            session_metadata: {}
          )

          bind_pairing_request!(pairing_request, session)
        end
      end

      def existing_dm_session
        ChannelSession.lock.find_by(
          installation_id: @context.ingress_binding.installation_id,
          ingress_binding_id: @context.ingress_binding.id,
          channel_connector_id: @context.channel_connector.id,
          peer_kind: "dm",
          peer_id: @context.envelope.external_sender_id,
          normalized_thread_key: ""
        )
      end

      def bind_pairing_request!(pairing_request, session)
        if pairing_request.channel_session != session
          pairing_request.update!(channel_session: session)
        end

        session
      end

      def resolved_execution_runtime
        @context.ingress_binding.default_execution_runtime ||
          @context.ingress_binding.workspace_agent.default_execution_runtime ||
          @context.ingress_binding.workspace_agent.agent.default_execution_runtime
      end
    end
  end
end
