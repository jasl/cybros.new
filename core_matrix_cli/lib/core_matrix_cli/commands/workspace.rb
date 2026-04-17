module CoreMatrixCLI
  module Commands
    class Workspace < Base
      def self.banner(command, *_args)
        "cmctl workspace #{command.usage}"
      end

      desc "list", "List available workspaces"
      def list
        with_cli_errors do
          return unless require_base_url!

          build_use_case(UseCases::ListWorkspaces).call.fetch("workspaces", []).each do |workspace|
            marker = workspace["is_default"] ? "*" : "-"
            say("#{marker} #{workspace.fetch("workspace_id")} #{workspace.fetch("name")}")
          end
        end
      end

      option :name, type: :string, desc: "Workspace name"
      option :privacy, type: :string, default: "private", desc: "Workspace privacy"
      option :default, type: :boolean, default: false, desc: "Mark the workspace as default"
      desc "create", "Create a workspace"
      def create
        with_cli_errors do
          return unless require_base_url!

          payload = build_use_case(UseCases::CreateWorkspace).call(
            name: options[:name] || ask("Workspace Name:"),
            privacy: options[:privacy],
            is_default: options[:default]
          )
          workspace = payload.fetch("workspace")
          say("Selected workspace: #{workspace.fetch("workspace_id")}")
          say("Workspace name: #{workspace.fetch("name")}")
        end
      end

      desc "use WORKSPACE_ID", "Select a workspace"
      def use(workspace_id)
        with_cli_errors do
          build_use_case(UseCases::UseWorkspace).call(workspace_id: workspace_id)
          say("Selected workspace: #{workspace_id}")
        end
      end
    end
  end
end
