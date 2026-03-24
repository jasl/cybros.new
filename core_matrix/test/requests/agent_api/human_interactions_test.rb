require "test_helper"

class AgentApiHumanInteractionsTest < ActionDispatch::IntegrationTest
  test "creates workflow owned human interaction requests through the machine facing api" do
    context = build_human_interaction_context!
    registration = register_machine_api_for_context!(context)

    post "/agent_api/human_interactions",
      params: {
        workflow_node_id: context[:workflow_node].id,
        request_type: "ApprovalRequest",
        blocking: true,
        request_payload: { approval_scope: "publish" },
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    assert_equal "human_interactions_request", response_body["method_id"]
    assert_equal "ApprovalRequest", response_body["request_type"]
    assert_equal context[:workflow_run].id, response_body["workflow_run_id"]
    assert context[:workflow_run].reload.waiting?
    assert_equal ["human_interaction.opened"], ConversationEvent.live_projection(conversation: context[:conversation]).map(&:event_kind)
  end
end
