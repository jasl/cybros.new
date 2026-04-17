module CoreMatrixCLI
  module Commands
    class Agent < Base
      def self.banner(command, *_args)
        "cmctl agent #{command.usage}"
      end

      option :workspace_id, type: :string, desc: "Workspace public id"
      option :agent_id, type: :string, required: true, desc: "Agent public id"
      desc "attach", "Attach an agent to the selected workspace"
      def attach
        with_cli_errors do
          return unless require_base_url!

          workspace_id = options[:workspace_id] || selected_workspace_id
          return if workspace_id.nil?

          payload = build_use_case(UseCases::AttachAgent).call(
            workspace_id: workspace_id,
            agent_id: options.fetch(:agent_id)
          )
          workspace_agent = payload.fetch("workspace_agent")
          say("Selected workspace agent: #{workspace_agent.fetch("workspace_agent_id")}")
        end
      end
    end
  end
end
