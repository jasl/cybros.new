module AppAPI
  module WorkspaceAgents
    module IngressBindings
      class SessionsController < AppAPI::BaseController
        before_action :set_workspace_agent
        before_action :set_ingress_binding

        def index
          sessions = ChannelSession
            .where(installation_id: current_installation_id, ingress_binding_id: @ingress_binding.id)
            .order(:created_at)

          render_method_response(
            method_id: "ingress_binding_sessions_index",
            workspace_agent_id: @workspace_agent.public_id,
            ingress_binding_id: @ingress_binding.public_id,
            sessions: sessions.map { |channel_session| serialize_channel_session(channel_session) }
          )
        end

        def update
          channel_session = find_channel_session!
          attributes = {}
          attributes[:binding_state] = params.fetch(:binding_state) if params.key?(:binding_state)
          attributes[:conversation] = resolve_conversation if params.key?(:conversation_id)
          channel_session.update!(attributes)

          render_method_response(
            method_id: "ingress_binding_session_update",
            workspace_agent_id: @workspace_agent.public_id,
            ingress_binding_id: @ingress_binding.public_id,
            session: serialize_channel_session(channel_session.reload)
          )
        end

        private

        def set_workspace_agent
          @workspace_agent ||= find_workspace_agent!(workspace_agent_public_id)
        end

        def set_ingress_binding
          @ingress_binding ||= IngressBinding.find_by!(
            installation_id: current_installation_id,
            workspace_agent_id: @workspace_agent.id,
            public_id: ingress_binding_public_id
          )
        end

        def find_channel_session!
          ChannelSession.find_by!(
            installation_id: current_installation_id,
            ingress_binding_id: @ingress_binding.id,
            public_id: params.fetch(:session_id)
          )
        end

        def resolve_conversation
          conversation_lookup_scope(workspace: @workspace_agent.workspace)
            .find_by!(
              public_id: params.fetch(:conversation_id),
              workspace_agent_id: @workspace_agent.id
            )
        end

        def serialize_channel_session(channel_session)
          {
            "channel_session_id" => channel_session.public_id,
            "ingress_binding_id" => channel_session.ingress_binding.public_id,
            "channel_connector_id" => channel_session.channel_connector.public_id,
            "conversation_id" => channel_session.conversation.public_id,
            "platform" => channel_session.platform,
            "peer_kind" => channel_session.peer_kind,
            "peer_id" => channel_session.peer_id,
            "thread_key" => channel_session.thread_key,
            "binding_state" => channel_session.binding_state,
            "last_inbound_at" => channel_session.last_inbound_at&.iso8601(6),
            "last_outbound_at" => channel_session.last_outbound_at&.iso8601(6),
            "session_metadata" => channel_session.session_metadata,
          }.compact
        end

        def workspace_agent_public_id
          params[:workspace_agent_id].presence || params.fetch(:workspace_agent_workspace_agent_id)
        end

        def ingress_binding_public_id
          params[:ingress_binding_id].presence || params.fetch(:ingress_binding_ingress_binding_id)
        end
      end
    end
  end
end
