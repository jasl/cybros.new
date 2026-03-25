require "test_helper"

class AgentRuntimeResourceApiTest < ActionDispatch::IntegrationTest
  test "runtime resource endpoints keep stable method ids while capability snapshots stay separated from tool catalog metadata" do
    context = build_human_interaction_context!
    registration = register_machine_api_for_context!(context)
    Variables::Write.call(
      scope: "workspace",
      workspace: context[:workspace],
      key: "support_tier",
      typed_value_payload: { "type" => "string", "value" => "gold" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run]
    )

    post "/agent_api/conversation_variables/write",
      params: {
        workspace_id: context[:workspace].public_id,
        conversation_id: context[:conversation].public_id,
        key: "customer_name",
        typed_value_payload: { type: "string", value: "Acme China" },
        source_kind: "agent_runtime",
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :created

    get "/agent_api/conversation_variables/resolve",
      params: {
        workspace_id: context[:workspace].public_id,
        conversation_id: context[:conversation].public_id,
      },
      headers: agent_api_headers(registration[:machine_credential])

    assert_response :success
    resolve_body = JSON.parse(response.body)

    get "/agent_api/capabilities", headers: agent_api_headers(registration[:machine_credential])

    assert_response :success
    capabilities_body = JSON.parse(response.body)

    post "/agent_api/human_interactions",
      params: {
        workflow_node_id: context[:workflow_node].public_id,
        request_type: "ApprovalRequest",
        blocking: true,
        request_payload: { approval_scope: "publish" },
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :created
    human_interaction_body = JSON.parse(response.body)

    assert_equal "conversation_variables_resolve", resolve_body["method_id"]
    assert_equal context[:workspace].public_id, resolve_body["workspace_id"]
    assert_equal context[:conversation].public_id, resolve_body["conversation_id"]
    assert_equal "Acme China", resolve_body.dig("variables", "customer_name", "typed_value_payload", "value")
    assert_equal "gold", resolve_body.dig("variables", "support_tier", "typed_value_payload", "value")
    assert_equal "capabilities_refresh", capabilities_body["method_id"]
    assert capabilities_body["protocol_methods"].all? { |entry| entry.fetch("method_id").match?(/\A[a-z0-9_]+\z/) }
    assert capabilities_body["tool_catalog"].all? { |entry| entry.fetch("tool_name").match?(/\A[a-z0-9_]+\z/) }
    refute_equal capabilities_body["protocol_methods"].map { |entry| entry.fetch("method_id") }.sort,
      capabilities_body["tool_catalog"].map { |entry| entry.fetch("tool_name") }.sort
    assert_equal "human_interactions_request", human_interaction_body["method_id"]
    assert_equal context[:workflow_node].public_id, human_interaction_body["workflow_node_id"]
    assert_equal context[:workflow_run].public_id, human_interaction_body["workflow_run_id"]
  end
end
