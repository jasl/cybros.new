module CoreMatrixCLI
  module UseCases
    class SetupTelegramPolling < Base
      def call(workspace_agent_id:, bot_token:)
        ingress_binding_id = ensure_ingress_binding_id(platform: "telegram", workspace_agent_id: workspace_agent_id)

        authenticated_api.update_ingress_binding(
          workspace_agent_id: workspace_agent_id,
          ingress_binding_id: ingress_binding_id,
          channel_connector: {
            credential_ref_payload: {
              bot_token: bot_token,
            },
            config_payload: {},
          }
        ).fetch("ingress_binding")
      end
    end
  end
end
