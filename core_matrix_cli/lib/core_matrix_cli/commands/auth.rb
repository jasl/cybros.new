module CoreMatrixCLI
  module Commands
    class Auth < Base
      def self.banner(command, *_args)
        "cmctl auth #{command.usage}"
      end

      desc "login", "Log in as an operator"
      def login
        with_cli_errors do
          base_url = ensure_base_url!
          payload = build_use_case(UseCases::LoginOperator).call(
            base_url: base_url,
            email: ask("Operator Email:"),
            password: prompt_secret("Password:")
          )
          print_session(payload)
        end
      end

      desc "whoami", "Show the current operator session"
      def whoami
        with_cli_errors do
          return unless require_base_url!

          print_session(build_use_case(UseCases::ShowCurrentSession).call)
        end
      end

      desc "logout", "Log out the current operator session"
      def logout
        with_cli_errors do
          build_use_case(UseCases::LogoutOperator).call
          say("Authenticated: no")
        end
      end
    end
  end
end
