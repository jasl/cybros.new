module CoreMatrixCLI
  class AuthCLI < Thor
    desc "login", "Log in as an operator"
    def login; end

    desc "whoami", "Show the current operator session"
    def whoami; end

    desc "logout", "Log out the current operator session"
    def logout; end
  end

  class ProvidersCLI < Thor
    desc "codex SUBCOMMAND", "Manage the Codex provider"
    subcommand "codex", Class.new(Thor) do
      desc "login", "Authorize the Codex subscription"
      def login; end

      desc "status", "Show the Codex authorization status"
      def status; end

      desc "logout", "Revoke the Codex authorization"
      def logout; end
    end
  end

  class WorkspaceCLI < Thor
    desc "list", "List available workspaces"
    def list; end

    desc "create", "Create a workspace"
    def create; end

    desc "use WORKSPACE_ID", "Select a workspace"
    def use(_workspace_id); end
  end

  class AgentCLI < Thor
    desc "attach", "Attach an agent to the selected workspace"
    def attach; end
  end

  class IngressCLI < Thor
    desc "telegram SUBCOMMAND", "Manage Telegram ingress"
    subcommand "telegram", Class.new(Thor) do
      desc "setup", "Configure Telegram ingress"
      def setup; end
    end

    desc "weixin SUBCOMMAND", "Manage Weixin ingress"
    subcommand "weixin", Class.new(Thor) do
      desc "setup", "Configure Weixin ingress"
      def setup; end
    end
  end

  class CLI < Thor
    desc "init", "Bootstrap or continue operator setup"
    def init; end

    desc "status", "Show installation readiness"
    def status; end

    register AuthCLI, "auth", "auth SUBCOMMAND", "Manage operator authentication"
    register ProvidersCLI, "providers", "providers SUBCOMMAND", "Manage provider setup"
    register WorkspaceCLI, "workspace", "workspace SUBCOMMAND", "Manage workspaces"
    register AgentCLI, "agent", "agent SUBCOMMAND", "Manage workspace agent attachments"
    register IngressCLI, "ingress", "ingress SUBCOMMAND", "Manage ingress integrations"
  end
end
