module AppAPI
  module Workspaces
    class WorkspaceAgentsController < AppAPI::Workspaces::BaseController
      def create
        workspace_agent = WorkspaceAgent.create!(
          installation: current_user.installation,
          workspace: @workspace,
          agent: find_agent!(params.fetch(:agent_id)),
          default_execution_runtime: resolve_default_execution_runtime,
          global_instructions: resolve_global_instructions,
          settings_payload: resolve_settings_payload,
          capability_policy_payload: resolve_capability_policy_payload,
          entry_policy_payload: resolve_entry_policy_payload
        )

        render_method_response(
          method_id: "workspace_agent_create",
          status: :created,
          workspace_id: @workspace.public_id,
          workspace_agent: AppSurface::Presenters::WorkspaceAgentPresenter.call(workspace_agent: workspace_agent)
        )
      end

      def update
        workspace_agent = find_workspace_agent!(params.fetch(:workspace_agent_id), workspace: @workspace)
        attributes = {}
        attributes[:default_execution_runtime] = resolve_default_execution_runtime if params.key?(:default_execution_runtime_id)
        attributes[:global_instructions] = resolve_global_instructions if params.key?(:global_instructions)
        attributes[:settings_payload] = resolve_settings_payload if params.key?(:settings_payload)
        attributes[:capability_policy_payload] = resolve_capability_policy_payload if params.key?(:capability_policy_payload)
        attributes[:entry_policy_payload] = resolve_entry_policy_payload if params.key?(:entry_policy_payload)

        if params.key?(:lifecycle_state)
          attributes[:lifecycle_state] = params.fetch(:lifecycle_state)
          if params[:lifecycle_state] == "revoked"
            attributes[:revoked_at] = Time.current
            attributes[:revoked_reason_kind] = params[:revoked_reason_kind]
          end
        end

        workspace_agent.update!(attributes)

        render_method_response(
          method_id: "workspace_agent_update",
          workspace_id: @workspace.public_id,
          workspace_agent: AppSurface::Presenters::WorkspaceAgentPresenter.call(workspace_agent: workspace_agent.reload)
        )
      end

      private

      def resolve_default_execution_runtime
        return nil if params[:default_execution_runtime_id].blank?

        find_accessible_execution_runtime!(params.fetch(:default_execution_runtime_id))
      end

      def resolve_global_instructions
        params[:global_instructions].presence
      end

      def resolve_settings_payload
        coerce_json_object_param(:settings_payload)
      end

      def resolve_capability_policy_payload
        return {} if params[:capability_policy_payload].blank?

        params.fetch(:capability_policy_payload).to_unsafe_h
      end

      def resolve_entry_policy_payload
        return Conversation.default_interactive_entry_policy_payload if params[:entry_policy_payload].blank?

        params.fetch(:entry_policy_payload).to_unsafe_h
      end

      def coerce_json_object_param(key)
        value = params[key]
        return {} if value.blank?
        return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

        value
      end
    end
  end
end
