module AgentAPI
  class ConversationVariablesController < BaseController
    def get
      workspace, conversation = workspace_and_conversation_from_params
      variable = CanonicalStores::GetQuery.call(reference_owner: conversation, key: params.fetch(:key))

      render json: {
        method_id: "conversation_variables_get",
        workspace_id: workspace.public_id,
        conversation_id: conversation.public_id,
        key: params.fetch(:key),
        variable: serialize_variable(variable, conversation: conversation),
      }
    end

    def mget
      workspace, conversation = workspace_and_conversation_from_payload
      variables = CanonicalStores::MultiGetQuery.call(
        reference_owner: conversation,
        keys: request_payload.fetch("keys")
      )

      render json: {
        method_id: "conversation_variables_mget",
        workspace_id: workspace.public_id,
        conversation_id: conversation.public_id,
        variables: variables.transform_values { |variable| serialize_variable(variable, conversation: conversation) },
      }
    end

    def exists
      workspace, conversation = workspace_and_conversation_from_params
      variable = CanonicalStores::GetQuery.call(reference_owner: conversation, key: params.fetch(:key))

      render json: {
        method_id: "conversation_variables_exists",
        workspace_id: workspace.public_id,
        conversation_id: conversation.public_id,
        key: params.fetch(:key),
        exists: variable.present?,
      }
    end

    def list_keys
      workspace, conversation = workspace_and_conversation_from_params
      page = CanonicalStores::ListKeysQuery.call(
        reference_owner: conversation,
        cursor: params[:cursor],
        limit: params[:limit]
      )

      render json: {
        method_id: "conversation_variables_list_keys",
        workspace_id: workspace.public_id,
        conversation_id: conversation.public_id,
        items: page.items.map { |item| serialize_variable_metadata(item, conversation: conversation) },
        next_cursor: page.next_cursor,
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
        variables: variables.transform_values { |variable| serialize_variable(variable, conversation: conversation) },
      }
    end

    def set
      workspace, conversation = workspace_and_conversation_from_payload
      variable = CanonicalStores::Set.call(
        conversation: conversation,
        key: request_payload.fetch("key"),
        typed_value_payload: request_payload.fetch("typed_value_payload")
      )

      render json: {
        method_id: "conversation_variables_set",
        variable: serialize_variable(variable, conversation: conversation),
      }, status: :created
    end

    def delete
      workspace, conversation = workspace_and_conversation_from_payload
      deleted = CanonicalStores::DeleteKey.call(
        conversation: conversation,
        key: request_payload.fetch("key")
      )

      render json: {
        method_id: "conversation_variables_delete",
        workspace_id: workspace.public_id,
        conversation_id: conversation.public_id,
        key: request_payload.fetch("key"),
        deleted: deleted.nil? ? false : true,
      }
    end

    def promote
      workspace, conversation = workspace_and_conversation_from_payload
      variable = Variables::PromoteToWorkspace.call(
        conversation: conversation,
        key: request_payload.fetch("key"),
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
  end
end
