module CoreMatrixCLI
  class CLI < Commands::Base
    package_name "cmctl"

    desc "init", "Bootstrap or continue operator setup"
    def init
      with_cli_errors do
        result = build_use_case(UseCases::RunInit).call(
          base_url: ask("CoreMatrix Base URL:"),
          ask: ->(prompt) { ask(prompt) },
          ask_secret: ->(prompt) { prompt_secret(prompt) }
        )

        installation_name = result.dig(:payload, "installation", "name")
        say("Installation: #{installation_name}") if installation_name
        print_snapshot(result.fetch(:snapshot))
      end
    end

    desc "status", "Show installation readiness"
    def status
      with_cli_errors do
        return unless require_base_url!

        print_snapshot(build_use_case(UseCases::ShowStatus).call)
      end
    end

    register Commands::Auth, "auth", "auth SUBCOMMAND", "Manage operator authentication"
    register Commands::Providers, "providers", "providers SUBCOMMAND", "Manage provider setup"
    register Commands::Workspace, "workspace", "workspace SUBCOMMAND", "Manage workspaces"
    register Commands::Agent, "agent", "agent SUBCOMMAND", "Manage workspace agent attachments"
    register Commands::Ingress, "ingress", "ingress SUBCOMMAND", "Manage ingress integrations"

    desc "version", "Print the CoreMatrix CLI version"
    map %w[-v --version] => :version
    def version
      puts CoreMatrixCLI::VERSION
    end
  end
end
