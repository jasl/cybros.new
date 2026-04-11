require "test_helper"

class AgentApiHumanInteractionsTest < ActionDispatch::IntegrationTest
  test "creates workflow owned human interaction requests through the machine facing api" do
    context = build_human_interaction_context!
    registration = register_machine_api_for_context!(context)

    post "/agent_api/human_interactions",
      params: {
        workflow_node_id: context[:workflow_node].public_id,
        request_type: "ApprovalRequest",
        blocking: true,
        request_payload: { approval_scope: "publish" },
      },
      headers: agent_api_headers(registration[:agent_connection_credential]),
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    request = HumanInteractionRequest.find_by_public_id!(response_body.fetch("request_id"))

    assert_equal "human_interactions_request", response_body["method_id"]
    assert_equal request.public_id, response_body["request_id"]
    assert_equal "ApprovalRequest", response_body["request_type"]
    assert_equal context[:workflow_run].public_id, response_body["workflow_run_id"]
    assert_equal context[:workflow_node].public_id, response_body["workflow_node_id"]
    assert context[:workflow_run].reload.waiting?
    assert_equal ["human_interaction.opened"], ConversationEvent.live_projection(conversation: context[:conversation]).map(&:event_kind)
    refute_includes response.body, %("#{context[:workflow_run].id}")
  end

  test "rejects raw bigint workflow node ids" do
    context = build_human_interaction_context!
    registration = register_machine_api_for_context!(context)

    post "/agent_api/human_interactions",
      params: {
        workflow_node_id: context[:workflow_node].id,
        request_type: "ApprovalRequest",
        blocking: true,
        request_payload: { approval_scope: "publish" },
      },
      headers: agent_api_headers(registration[:agent_connection_credential]),
      as: :json

    assert_response :not_found
  end
end
