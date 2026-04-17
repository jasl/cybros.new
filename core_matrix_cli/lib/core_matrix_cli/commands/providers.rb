module CoreMatrixCLI
  module Commands
    class Providers < Base
      def self.banner(command, *_args)
        "cmctl providers #{command.usage}"
      end

      class Codex < Base
        def self.banner(command, *_args)
          "cmctl providers codex #{command.usage}"
        end

        desc "login", "Authorize the Codex subscription"
        def login
          with_cli_errors do
            return unless require_base_url!

            result = build_use_case(UseCases::AuthorizeCodexSubscription).call
            print_codex_authorization(result.fetch(:initial_authorization))
            say("Waiting for authorization...")
            print_codex_authorization(result.fetch(:final_authorization))
          end
        end

        desc "status", "Show the Codex authorization status"
        def status
          with_cli_errors do
            return unless require_base_url!

            payload = build_use_case(UseCases::ShowCodexStatus).call
            print_codex_authorization(payload.fetch("authorization"))
          end
        end

        desc "logout", "Revoke the Codex authorization"
        def logout
          with_cli_errors do
            return unless require_base_url!

            payload = build_use_case(UseCases::RevokeCodexAuthorization).call
            say("codex subscription: #{payload.dig("authorization", "status")}")
          end
        end
      end

      desc "codex SUBCOMMAND", "Manage the Codex provider"
      subcommand "codex", Codex
    end
  end
end
