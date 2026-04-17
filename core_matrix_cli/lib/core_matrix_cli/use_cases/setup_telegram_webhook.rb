module CoreMatrixCLI
  module UseCases
    class SetupTelegramWebhook < Base
      def call(workspace_agent_id:, bot_token:, webhook_base_url:)
        ingress_binding_id = ensure_ingress_binding_id(platform: "telegram_webhook", workspace_agent_id: workspace_agent_id)

        authenticated_api.update_ingress_binding(
          workspace_agent_id: workspace_agent_id,
          ingress_binding_id: ingress_binding_id,
          channel_connector: {
            credential_ref_payload: {
              bot_token: bot_token,
            },
            config_payload: {
              webhook_base_url: normalize_base_url(webhook_base_url),
            },
          }
        ).fetch("ingress_binding")
      end
    end
  end
end
