module AppAPI
  module WorkspaceAgents
    class IngressBindingsController < AppAPI::BaseController
      PLATFORM_CONNECTOR_DEFAULTS = {
        "telegram" => {
          driver: "telegram_bot_api",
          transport_kind: "poller",
        },
        "telegram_webhook" => {
          driver: "telegram_bot_api",
          transport_kind: "webhook",
        },
        "weixin" => {
          driver: "claw_bot_sdk_weixin",
          transport_kind: "poller",
        },
      }.freeze

      before_action :set_workspace_agent
      before_action :set_ingress_binding, only: [:show, :update, :weixin_start_login, :weixin_login_status, :weixin_disconnect]

      def show
        render_method_response(
          method_id: "ingress_binding_show",
          workspace_agent_id: @workspace_agent.public_id,
          ingress_binding: serialize_ingress_binding(@ingress_binding)
        )
      end

      def create
        platform = params.fetch(:platform)
        connector_defaults = PLATFORM_CONNECTOR_DEFAULTS.fetch(platform)
        plaintext_secret_token, secret_digest = IngressBinding.issue_ingress_secret

        ingress_binding = nil
        IngressBinding.transaction do
          ingress_binding = IngressBinding.create!(
            installation: current_user.installation,
            workspace_agent: @workspace_agent,
            default_execution_runtime: resolve_default_execution_runtime,
            ingress_secret_digest: secret_digest,
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
          ingress_binding: serialize_ingress_binding(
            ingress_binding.reload,
            plaintext_secret_token: plaintext_secret_token
          )
        )
      end

      def update
        attributes = {}
        attributes[:default_execution_runtime] = resolve_default_execution_runtime if params.key?(:default_execution_runtime_id)
        attributes[:lifecycle_state] = params.fetch(:lifecycle_state) if params.key?(:lifecycle_state)
        plaintext_secret_token = nil

        IngressBinding.transaction do
          @ingress_binding.update!(attributes) if attributes.present?

          if params[:lifecycle_state] == "disabled"
            @ingress_binding.channel_connectors.where(lifecycle_state: "active").update_all(
              lifecycle_state: "disabled",
              updated_at: Time.current
            )
          end

          if params.key?(:channel_connector)
            ::IngressBindings::UpdateConnector.call(
              channel_connector: @ingress_binding.channel_connectors.order(:id).last,
              attributes: params.require(:channel_connector).permit(
                :label,
                :lifecycle_state,
                credential_ref_payload: {},
                config_payload: {}
              ).to_h
            )
          end

          plaintext_secret_token = reissue_setup_secret! if ActiveModel::Type::Boolean.new.cast(params[:reissue_setup_secret])
        end

        render_method_response(
          method_id: "ingress_binding_update",
          workspace_agent_id: @workspace_agent.public_id,
          ingress_binding: serialize_ingress_binding(
            @ingress_binding.reload,
            plaintext_secret_token: plaintext_secret_token
          )
        )
      end

      def weixin_start_login
        render_method_response(
          method_id: "ingress_binding_weixin_start_login",
          workspace_agent_id: @workspace_agent.public_id,
          ingress_binding_id: @ingress_binding.public_id,
          weixin: ClawBotSDK::Weixin::QrLogin.start(channel_connector: weixin_channel_connector)
        )
      end

      def weixin_login_status
        render_method_response(
          method_id: "ingress_binding_weixin_login_status",
          workspace_agent_id: @workspace_agent.public_id,
          ingress_binding_id: @ingress_binding.public_id,
          weixin: ClawBotSDK::Weixin::QrLogin.status(channel_connector: weixin_channel_connector)
        )
      end

      def weixin_disconnect
        channel_connector = weixin_channel_connector
        ClawBotSDK::Weixin::QrLogin.disconnect!(channel_connector: channel_connector)

        render_method_response(
          method_id: "ingress_binding_weixin_disconnect",
          workspace_agent_id: @workspace_agent.public_id,
          ingress_binding_id: @ingress_binding.public_id,
          channel_connector: serialize_channel_connector(channel_connector.reload)
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

      def weixin_channel_connector
        @weixin_channel_connector ||= @ingress_binding.channel_connectors.find_by!(platform: "weixin")
      end

      def serialize_ingress_binding(ingress_binding, plaintext_secret_token: nil)
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
          "setup" => setup_payload_for(ingress_binding, connector, plaintext_secret_token: plaintext_secret_token),
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
          "configured" => channel_connector_configured?(connector),
        }
      end

      def setup_payload_for(ingress_binding, connector, plaintext_secret_token: nil)
        return {} if connector.blank?

        case connector.platform
        when "telegram"
          {
            "platform" => "telegram",
            "poller_binding_id" => ingress_binding.public_ingress_id,
          }
        when "telegram_webhook"
          {
            "platform" => "telegram_webhook",
            "webhook_path" => "/ingress_api/telegram/bindings/#{ingress_binding.public_ingress_id}/updates",
            "webhook_secret_token" => plaintext_secret_token,
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

      def reissue_setup_secret!
        plaintext_secret_token, secret_digest = IngressBinding.issue_ingress_secret
        @ingress_binding.update!(ingress_secret_digest: secret_digest)
        plaintext_secret_token
      end

      def channel_connector_configured?(connector)
        case connector.platform
        when "telegram"
          connector.bot_token.present?
        when "telegram_webhook"
          connector.bot_token.present? && connector.webhook_base_url.present?
        else
          connector.lifecycle_state == "active"
        end
      end
    end
  end
end
