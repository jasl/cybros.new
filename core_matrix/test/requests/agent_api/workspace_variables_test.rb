require "test_helper"

class AgentApiWorkspaceVariablesTest < ActionDispatch::IntegrationTest
  test "read endpoints expose workspace get mget and list semantics" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    region = Variables::Write.call(
      scope: "workspace",
      workspace: context[:workspace],
      key: "region",
      typed_value_payload: { "type" => "string", "value" => "cn" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run]
    )
    support_tier = Variables::Write.call(
      scope: "workspace",
      workspace: context[:workspace],
      key: "support_tier",
      typed_value_payload: { "type" => "string", "value" => "gold" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run]
    )

    get "/agent_api/workspace_variables/get",
      params: {
        workspace_id: context[:workspace].id,
        key: "support_tier",
      },
      headers: agent_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "workspace_variables_get", response_body["method_id"]
    assert_equal support_tier.id, response_body.dig("variable", "id")

    post "/agent_api/workspace_variables/mget",
      params: {
        workspace_id: context[:workspace].id,
        keys: %w[support_tier region missing],
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "workspace_variables_mget", response_body["method_id"]
    assert_equal support_tier.id, response_body.dig("variables", "support_tier", "id")
    assert_equal region.id, response_body.dig("variables", "region", "id")
    assert_nil response_body.dig("variables", "missing")

    get "/agent_api/workspace_variables",
      params: {
        workspace_id: context[:workspace].id,
      },
      headers: agent_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "workspace_variables_list", response_body["method_id"]
    assert_equal %w[region support_tier], response_body["variables"].map { |variable| variable.fetch("key") }
  end

  test "write endpoint materializes kernel owned workspace variables" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    post "/agent_api/workspace_variables/write",
      params: {
        workspace_id: context[:workspace].id,
        key: "region",
        typed_value_payload: { type: "string", value: "cn" },
        source_kind: "agent_runtime",
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    assert_equal "workspace_variables_write", response_body["method_id"]
    assert_equal "workspace", response_body.dig("variable", "scope")
    assert_equal "cn", response_body.dig("variable", "typed_value_payload", "value")

    variable = CanonicalVariable.find(response_body.dig("variable", "id"))
    assert_equal registration[:deployment], variable.writer
  end
end
