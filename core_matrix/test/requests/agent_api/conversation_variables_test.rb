require "test_helper"

class AgentApiConversationVariablesTest < ActionDispatch::IntegrationTest
  test "read endpoints expose get mget exists list_keys and resolve semantics with stable method ids" do
    context = build_canonical_variable_context!
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
    LineageStores::Set.call(
      conversation: context[:conversation],
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme China" }
    )
    LineageStores::Set.call(
      conversation: context[:conversation],
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" }
    )

    get "/agent_api/conversation_variables/get",
      params: {
        workspace_id: context[:workspace].public_id,
        conversation_id: context[:conversation].public_id,
        key: "customer_name",
      },
      headers: agent_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_get", response_body["method_id"]
    assert_equal context[:workspace].public_id, response_body["workspace_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    assert_equal "conversation", response_body.dig("variable", "scope")
    refute response_body.fetch("variable").key?("id")
    assert_equal context[:workspace].public_id, response_body.dig("variable", "workspace_id")
    assert_equal context[:conversation].public_id, response_body.dig("variable", "conversation_id")
    assert_equal "Acme China", response_body.dig("variable", "typed_value_payload", "value")

    post "/agent_api/conversation_variables/mget",
      params: {
        workspace_id: context[:workspace].public_id,
        conversation_id: context[:conversation].public_id,
        keys: %w[customer_name tone missing],
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_mget", response_body["method_id"]
    assert_equal context[:workspace].public_id, response_body["workspace_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    refute response_body.dig("variables", "customer_name").key?("id")
    refute response_body.dig("variables", "tone").key?("id")
    assert_nil response_body.dig("variables", "missing")

    get "/agent_api/conversation_variables/exists",
      params: {
        workspace_id: context[:workspace].public_id,
        conversation_id: context[:conversation].public_id,
        key: "tone",
      },
      headers: agent_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_exists", response_body["method_id"]
    assert_equal true, response_body["exists"]

    get "/agent_api/conversation_variables/list_keys",
      params: {
        workspace_id: context[:workspace].public_id,
        conversation_id: context[:conversation].public_id,
      },
      headers: agent_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_list_keys", response_body["method_id"]
    assert_equal context[:workspace].public_id, response_body["workspace_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    assert_equal %w[customer_name tone], response_body["items"].map { |item| item.fetch("key") }
    refute response_body["items"].first.key?("typed_value_payload")

    get "/agent_api/conversation_variables/resolve",
      params: {
        workspace_id: context[:workspace].public_id,
        conversation_id: context[:conversation].public_id,
      },
      headers: agent_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_resolve", response_body["method_id"]
    assert_equal context[:workspace].public_id, response_body["workspace_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    assert_equal "Acme China", response_body.dig("variables", "customer_name", "typed_value_payload", "value")
    assert_equal "gold", response_body.dig("variables", "support_tier", "typed_value_payload", "value")
    refute response_body.dig("variables", "customer_name").key?("id")
  end

  test "set delete and promote endpoints use the lineage store and workspace promotion" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    post "/agent_api/conversation_variables/set",
      params: {
        workspace_id: context[:workspace].public_id,
        conversation_id: context[:conversation].public_id,
        key: "customer_name",
        typed_value_payload: { type: "string", value: "Acme China" },
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :created
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_set", response_body["method_id"]
    assert_equal "conversation", response_body.dig("variable", "scope")
    assert_equal "Acme China", response_body.dig("variable", "typed_value_payload", "value")
    refute response_body.fetch("variable").key?("id")

    assert_equal "Acme China",
      LineageStores::GetQuery.call(reference_owner: context[:conversation], key: "customer_name").typed_value_payload["value"]

    post "/agent_api/conversation_variables/promote",
      params: {
        workspace_id: context[:workspace].public_id,
        conversation_id: context[:conversation].public_id,
        key: "customer_name",
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :created
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_promote", response_body["method_id"]
    assert_equal "workspace", response_body.dig("variable", "scope")
    assert_equal "Acme China", response_body.dig("variable", "typed_value_payload", "value")
    refute response_body.fetch("variable").key?("id")

    post "/agent_api/conversation_variables/delete",
      params: {
        workspace_id: context[:workspace].public_id,
        conversation_id: context[:conversation].public_id,
        key: "customer_name",
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_delete", response_body["method_id"]
    assert_equal true, response_body["deleted"]
    assert_nil LineageStores::GetQuery.call(reference_owner: context[:conversation], key: "customer_name")
  end

  test "set rejects raw bigint identifiers" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    post "/agent_api/conversation_variables/set",
      params: {
        workspace_id: context[:workspace].id,
        conversation_id: context[:conversation].id,
        key: "customer_name",
        typed_value_payload: { type: "string", value: "Acme China" },
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :not_found
  end
end
