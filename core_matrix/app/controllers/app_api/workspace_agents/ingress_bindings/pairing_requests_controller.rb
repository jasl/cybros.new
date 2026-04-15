module AppAPI
  module WorkspaceAgents
    module IngressBindings
      class PairingRequestsController < AppAPI::BaseController
        before_action :set_workspace_agent
        before_action :set_ingress_binding

        def index
          pairing_requests = ChannelPairingRequest
            .where(installation_id: current_installation_id, ingress_binding_id: @ingress_binding.id)
            .order(:created_at)

          render_method_response(
            method_id: "ingress_binding_pairing_requests_index",
            workspace_agent_id: @workspace_agent.public_id,
            ingress_binding_id: @ingress_binding.public_id,
            pairing_requests: pairing_requests.map { |pairing_request| serialize_pairing_request(pairing_request) }
          )
        end

        def update
          pairing_request = find_pairing_request!
          lifecycle_state = params.fetch(:lifecycle_state)
          attributes = { lifecycle_state: lifecycle_state }

          case lifecycle_state
          when "approved"
            attributes[:approved_at] = Time.current
          when "rejected"
            attributes[:rejected_at] = Time.current
          end

          pairing_request.update!(attributes)

          render_method_response(
            method_id: "ingress_binding_pairing_request_update",
            workspace_agent_id: @workspace_agent.public_id,
            ingress_binding_id: @ingress_binding.public_id,
            pairing_request: serialize_pairing_request(pairing_request.reload)
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

        def find_pairing_request!
          ChannelPairingRequest.find_by!(
            installation_id: current_installation_id,
            ingress_binding_id: @ingress_binding.id,
            public_id: params.fetch(:pairing_request_id)
          )
        end

        def serialize_pairing_request(pairing_request)
          {
            "pairing_request_id" => pairing_request.public_id,
            "ingress_binding_id" => pairing_request.ingress_binding.public_id,
            "channel_connector_id" => pairing_request.channel_connector.public_id,
            "channel_session_id" => pairing_request.channel_session&.public_id,
            "platform_sender_id" => pairing_request.platform_sender_id,
            "sender_snapshot" => pairing_request.sender_snapshot,
            "lifecycle_state" => pairing_request.lifecycle_state,
            "expires_at" => pairing_request.expires_at&.iso8601(6),
            "approved_at" => pairing_request.approved_at&.iso8601(6),
            "rejected_at" => pairing_request.rejected_at&.iso8601(6),
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
