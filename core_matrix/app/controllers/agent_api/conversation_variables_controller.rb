module AgentAPI
  class ConversationVariablesController < BaseController
    def index
      workspace, conversation = workspace_and_conversation_from_params
      variables = ConversationVariables::ListQuery.call(
        workspace: workspace,
        conversation: conversation
      )

      render json: {
        method_id: "conversation_variables_list",
        workspace_id: workspace.public_id,
        conversation_id: conversation.public_id,
        variables: variables.map { |variable| serialize_variable(variable) },
      }
    end

    def show_value
      workspace, conversation = workspace_and_conversation_from_params
      variable = ConversationVariables::GetQuery.call(
        workspace: workspace,
        conversation: conversation,
        key: params.fetch(:key)
      )

      render json: {
        method_id: "conversation_variables_get",
        workspace_id: workspace.public_id,
        conversation_id: conversation.public_id,
        key: params.fetch(:key),
        variable: serialize_variable(variable),
      }
    end

    def bulk_show
      workspace, conversation = workspace_and_conversation_from_payload
      variables = ConversationVariables::MgetQuery.call(
        workspace: workspace,
        conversation: conversation,
        keys: request_payload.fetch("keys")
      )

      render json: {
        method_id: "conversation_variables_mget",
        workspace_id: workspace.public_id,
        conversation_id: conversation.public_id,
        variables: variables.transform_values { |variable| serialize_variable(variable) },
      }
    end

    def resolve
      workspace, conversation = workspace_and_conversation_from_params
      variables = ConversationVariables::ResolveQuery.call(
        workspace: workspace,
        conversation: conversation
      )

      render json: {
        method_id: "conversation_variables_resolve",
        workspace_id: workspace.public_id,
        conversation_id: conversation.public_id,
        variables: variables.transform_values { |variable| serialize_variable(variable) },
      }
    end

    def write
      workspace, conversation = workspace_and_conversation_from_payload
      variable = Variables::Write.call(
        scope: "conversation",
        workspace: workspace,
        conversation: conversation,
        key: request_payload.fetch("key"),
        typed_value_payload: request_payload.fetch("typed_value_payload"),
        writer: current_deployment,
        source_kind: request_payload.fetch("source_kind"),
        source_turn: optional_turn(request_payload["source_turn_id"]),
        source_workflow_run: optional_workflow_run(request_payload["source_workflow_run_id"]),
        projection_policy: request_payload.fetch("projection_policy", "silent")
      )

      render json: {
        method_id: "conversation_variables_write",
        variable: serialize_variable(variable),
      }, status: :created
    end

    def promote
      workspace, conversation = workspace_and_conversation_from_payload
      conversation_variable = ConversationVariables::GetQuery.call(
        workspace: workspace,
        conversation: conversation,
        key: request_payload.fetch("key")
      )
      raise ActiveRecord::RecordNotFound, "conversation variable is missing" if conversation_variable.blank?

      variable = Variables::PromoteToWorkspace.call(
        conversation_variable: conversation_variable,
        writer: current_deployment
      )

      render json: {
        method_id: "conversation_variables_promote",
        variable: serialize_variable(variable),
      }, status: :created
    end

    private

    def workspace_and_conversation_from_params
      workspace = find_workspace!(params.fetch(:workspace_id))
      conversation = find_conversation!(params.fetch(:conversation_id), workspace: workspace)
      [workspace, conversation]
    end

    def workspace_and_conversation_from_payload
      workspace = find_workspace!(request_payload.fetch("workspace_id"))
      conversation = find_conversation!(request_payload.fetch("conversation_id"), workspace: workspace)
      [workspace, conversation]
    end

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
