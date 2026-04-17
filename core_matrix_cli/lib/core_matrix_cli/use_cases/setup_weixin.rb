module CoreMatrixCLI
  module UseCases
    class SetupWeixin < Base
      POLL_TIMEOUT = 10
      POLL_INTERVAL = 0.01

      def call(workspace_agent_id:)
        ingress_binding_id = ensure_ingress_binding_id(platform: "weixin", workspace_agent_id: workspace_agent_id)

        authenticated_api.start_weixin_login(
          workspace_agent_id: workspace_agent_id,
          ingress_binding_id: ingress_binding_id
        )

        outputs = []
        last_qr_text = nil
        last_qr_code_url = nil

        final_payload = polling.until(
          timeout: POLL_TIMEOUT,
          interval: POLL_INTERVAL,
          stop_on: ->(payload) { payload.dig("weixin", "login_state") != "pending" }
        ) do
          payload = authenticated_api.weixin_login_status(
            workspace_agent_id: workspace_agent_id,
            ingress_binding_id: ingress_binding_id
          )
          qr_text = payload.dig("weixin", "qr_text")
          qr_code_url = payload.dig("weixin", "qr_code_url")

          if qr_text && qr_text != last_qr_text
            outputs << qr_renderer.render(qr_text)
            last_qr_text = qr_text
          elsif qr_code_url && qr_code_url != last_qr_code_url
            outputs << "QR Code URL: #{qr_code_url}"
            last_qr_code_url = qr_code_url
          end

          payload
        end

        {
          ingress_binding_id: ingress_binding_id,
          outputs: outputs,
          payload: final_payload,
        }
      end
    end
  end
end
