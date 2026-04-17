module CoreMatrixCLI
  module Commands
    class Ingress < Base
      def self.banner(command, *_args)
        "cmctl ingress #{command.usage}"
      end

      class Telegram < Base
        def self.banner(command, *_args)
          "cmctl ingress telegram #{command.usage}"
        end

        long_desc <<~HELP
          Preparation:
            - Create a bot in BotFather
            - Copy the bot token
            - Ensure the recurring scheduler and queue worker are running for polling
            - Use a bot token that is not also assigned to Telegram webhook mode

          This command will ask for:
            - bot token

          This command will print:
            - poller binding id

          Transport notes:
            - polling does not require a public HTTPS base URL
            - polling and webhook require different Telegram bot tokens

          v1 verification boundary:
            - API-contract only, not real poll delivery
        HELP
        desc "setup", "Configure Telegram ingress"
        def setup
          with_cli_errors do
            return unless require_base_url!

            workspace_agent_id = selected_workspace_agent_id!
            return if workspace_agent_id.nil?

            updated_binding = build_use_case(UseCases::SetupTelegramPolling).call(
              workspace_agent_id: workspace_agent_id,
              bot_token: ask("Telegram Bot Token:")
            )

            setup = updated_binding.fetch("setup")
            say("Polling Binding ID: #{setup.fetch("poller_binding_id")}")
            say("Next: ensure recurring scheduler and queue workers are running for Telegram polling.")
          end
        end
      end

      class TelegramWebhook < Base
        def self.banner(command, *_args)
          "cmctl ingress telegram-webhook #{command.usage}"
        end

        long_desc <<~HELP
          Preparation:
            - Create a bot in BotFather
            - Copy the bot token
            - Prepare a public HTTPS base URL for CoreMatrix
            - Use a bot token that is not also assigned to Telegram polling

          This command will ask for:
            - bot token
            - webhook base URL

          This command will print:
            - webhook URL
            - webhook secret header name
            - webhook secret token

          Transport notes:
            - polling and webhook require different Telegram bot tokens

          v1 verification boundary:
            - API-contract only, not real webhook delivery
        HELP
        desc "setup", "Configure Telegram webhook ingress"
        def setup
          with_cli_errors do
            return unless require_base_url!

            workspace_agent_id = selected_workspace_agent_id!
            return if workspace_agent_id.nil?

            bot_token = ask("Telegram Bot Token:")
            webhook_base_url = ask("Webhook Base URL:")
            updated_binding = build_use_case(UseCases::SetupTelegramWebhook).call(
              workspace_agent_id: workspace_agent_id,
              bot_token: bot_token,
              webhook_base_url: webhook_base_url
            )

            setup = updated_binding.fetch("setup")
            normalized_base_url = webhook_base_url.to_s.strip.sub(%r{/+\z}, "")
            webhook_url = "#{normalized_base_url}#{setup.fetch("webhook_path")}"

            say("Webhook URL: #{webhook_url}")
            say("Webhook Secret Header: X-Telegram-Bot-Api-Secret-Token")
            say("Webhook Secret Token: #{setup.fetch("webhook_secret_token")}")
            say("Next: register the webhook URL and secret token with Telegram.")
          end
        end
      end

      class Weixin < Base
        def self.banner(command, *_args)
          "cmctl ingress weixin #{command.usage}"
        end

        long_desc <<~HELP
          Preparation:
            - Ensure you are logged in
            - Ensure a workspace and workspace agent are selected
            - Use a terminal that can render ANSI QR output if possible

          This command will:
            - create or reuse the binding
            - start login when needed
            - poll status
            - render ANSI QR from qr_text when available
            - print qr_code_url only as a fallback

          v1 verification boundary:
            - API-contract only, not real account scanning or live message delivery
        HELP
        desc "setup", "Configure Weixin ingress"
        def setup
          with_cli_errors do
            return unless require_base_url!

            workspace_agent_id = selected_workspace_agent_id!
            return if workspace_agent_id.nil?

            result = build_use_case(UseCases::SetupWeixin).call(workspace_agent_id: workspace_agent_id)
            result.fetch(:outputs).each { |line| say(line) }
            say("weixin status: #{result.dig(:payload, "weixin", "login_state")}")
          end
        end
      end

      register Telegram, "telegram", "telegram SUBCOMMAND", "Manage Telegram ingress"
      map "telegram-webhook" => "telegram_webhook"
      register TelegramWebhook, "telegram_webhook", "telegram-webhook SUBCOMMAND", "Manage Telegram webhook ingress"
      register Weixin, "weixin", "weixin SUBCOMMAND", "Manage Weixin ingress"
    end
  end
end
