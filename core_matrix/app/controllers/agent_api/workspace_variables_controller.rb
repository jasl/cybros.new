module AgentAPI
  class WorkspaceVariablesController < BaseController
    def index
      workspace = find_workspace!(params.fetch(:workspace_id))
      variables = WorkspaceVariables::ListQuery.call(workspace: workspace)

      render json: {
        method_id: "workspace_variables_list",
        workspace_id: workspace.public_id,
        variables: variables.map { |variable| serialize_variable(variable) },
      }
    end

    def show_value
      workspace = find_workspace!(params.fetch(:workspace_id))
      variable = WorkspaceVariables::GetQuery.call(
        workspace: workspace,
        key: params.fetch(:key)
      )

      render json: {
        method_id: "workspace_variables_get",
        workspace_id: workspace.public_id,
        key: params.fetch(:key),
        variable: serialize_variable(variable),
      }
    end

    def bulk_show
      workspace = find_workspace!(request_payload.fetch("workspace_id"))
      variables = WorkspaceVariables::MgetQuery.call(
        workspace: workspace,
        keys: request_payload.fetch("keys")
      )

      render json: {
        method_id: "workspace_variables_mget",
        workspace_id: workspace.public_id,
        variables: variables.transform_values { |variable| serialize_variable(variable) },
      }
    end

    def write
      workspace = find_workspace!(request_payload.fetch("workspace_id"))
      variable = Variables::Write.call(
        scope: "workspace",
        workspace: workspace,
        key: request_payload.fetch("key"),
        typed_value_payload: request_payload.fetch("typed_value_payload"),
        writer: current_agent_snapshot,
        source_kind: request_payload.fetch("source_kind"),
        source_turn: optional_turn(request_payload["source_turn_id"]),
        source_workflow_run: optional_workflow_run(request_payload["source_workflow_run_id"]),
        projection_policy: request_payload.fetch("projection_policy", "silent")
      )

      render json: {
        method_id: "workspace_variables_write",
        variable: serialize_variable(variable),
      }, status: :created
    end

    private

    def optional_turn(turn_id)
      return if turn_id.blank?

      find_turn!(turn_id)
    end

    def optional_workflow_run(workflow_run_id)
      return if workflow_run_id.blank?

      find_workflow_run!(workflow_run_id)
    end
  end
end
