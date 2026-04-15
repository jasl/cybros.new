module AppAPI
  module WorkspaceAgents
    class IngressBindingsController < AppAPI::BaseController
      PLATFORM_CONNECTOR_DEFAULTS = {
        "telegram" => {
          driver: "telegram_bot_api",
          transport_kind: "webhook",
        },
        "weixin" => {
          driver: "claw_bot_sdk_weixin",
          transport_kind: "poller",
        },
      }.freeze

      before_action :set_workspace_agent
      before_action :set_ingress_binding, only: :update

      def create
        platform = params.fetch(:platform)
        connector_defaults = PLATFORM_CONNECTOR_DEFAULTS.fetch(platform)

        ingress_binding = nil
        IngressBinding.transaction do
          ingress_binding = IngressBinding.create!(
            installation: current_user.installation,
            workspace_agent: @workspace_agent,
            default_execution_runtime: resolve_default_execution_runtime,
            routing_policy_payload: {},
            manual_entry_policy: IngressBinding::DEFAULT_MANUAL_ENTRY_POLICY
          )

          ingress_binding.channel_connectors.create!(
            installation: current_user.installation,
            platform: platform,
            driver: connector_defaults.fetch(:driver),
            transport_kind: connector_defaults.fetch(:transport_kind),
            label: params[:label].presence || "#{platform.titleize} Binding",
            lifecycle_state: "active",
            credential_ref_payload: {},
            config_payload: {},
            runtime_state_payload: {}
          )
        end

        render_method_response(
          method_id: "ingress_binding_create",
          status: :created,
          workspace_agent_id: @workspace_agent.public_id,
          ingress_binding: serialize_ingress_binding(ingress_binding.reload)
        )
      end

      def update
        attributes = {}
        attributes[:default_execution_runtime] = resolve_default_execution_runtime if params.key?(:default_execution_runtime_id)
        attributes[:lifecycle_state] = params.fetch(:lifecycle_state) if params.key?(:lifecycle_state)

        IngressBinding.transaction do
          @ingress_binding.update!(attributes)

          if params[:lifecycle_state] == "disabled"
            @ingress_binding.channel_connectors.where(lifecycle_state: "active").update_all(
              lifecycle_state: "disabled",
              updated_at: Time.current
            )
          end
        end

        render_method_response(
          method_id: "ingress_binding_update",
          workspace_agent_id: @workspace_agent.public_id,
          ingress_binding: serialize_ingress_binding(@ingress_binding.reload)
        )
      end

      private

      def set_workspace_agent
        @workspace_agent ||= find_workspace_agent!(workspace_agent_public_id)
      end

      def set_ingress_binding
        @ingress_binding ||= IngressBinding
          .includes(:default_execution_runtime, channel_connectors: [])
          .find_by!(
            installation_id: current_installation_id,
            workspace_agent_id: @workspace_agent.id,
            public_id: ingress_binding_public_id
          )
      end

      def resolve_default_execution_runtime
        return nil if params[:default_execution_runtime_id].blank?

        find_accessible_execution_runtime!(params.fetch(:default_execution_runtime_id))
      end

      def serialize_ingress_binding(ingress_binding)
        connector = ingress_binding.channel_connectors.order(:id).last

        {
          "ingress_binding_id" => ingress_binding.public_id,
          "workspace_agent_id" => ingress_binding.workspace_agent.public_id,
          "default_execution_runtime_id" => ingress_binding.default_execution_runtime&.public_id,
          "lifecycle_state" => ingress_binding.lifecycle_state,
          "public_ingress_id" => ingress_binding.public_ingress_id,
          "routing_policy_payload" => ingress_binding.routing_policy_payload,
          "manual_entry_policy" => ingress_binding.manual_entry_policy,
          "channel_connector" => serialize_channel_connector(connector),
          "setup" => setup_payload_for(ingress_binding, connector),
        }.compact
      end

      def serialize_channel_connector(connector)
        return nil if connector.blank?

        {
          "channel_connector_id" => connector.public_id,
          "platform" => connector.platform,
          "driver" => connector.driver,
          "transport_kind" => connector.transport_kind,
          "label" => connector.label,
          "lifecycle_state" => connector.lifecycle_state,
        }
      end

      def setup_payload_for(ingress_binding, connector)
        return {} if connector.blank?

        case connector.platform
        when "telegram"
          {
            "platform" => "telegram",
            "webhook_path" => "/ingress_api/telegram/bindings/#{ingress_binding.public_ingress_id}/updates",
          }
        when "weixin"
          {
            "platform" => "weixin",
            "poller_binding_id" => ingress_binding.public_ingress_id,
          }
        else
          {}
        end
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
