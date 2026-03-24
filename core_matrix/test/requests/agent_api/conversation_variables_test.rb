require "test_helper"

class AgentApiConversationVariablesTest < ActionDispatch::IntegrationTest
  test "read endpoints expose get mget list and resolve semantics with stable method ids" do
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
    conversation_customer_name = Variables::Write.call(
      scope: "conversation",
      workspace: context[:workspace],
      conversation: context[:conversation],
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme China" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run]
    )
    tone = Variables::Write.call(
      scope: "conversation",
      workspace: context[:workspace],
      conversation: context[:conversation],
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run]
    )

    get "/agent_api/conversation_variables/get",
      params: {
        workspace_id: context[:workspace].id,
        conversation_id: context[:conversation].id,
        key: "customer_name",
      },
      headers: agent_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_get", response_body["method_id"]
    assert_equal conversation_customer_name.id, response_body.dig("variable", "id")

    post "/agent_api/conversation_variables/mget",
      params: {
        workspace_id: context[:workspace].id,
        conversation_id: context[:conversation].id,
        keys: %w[customer_name tone missing],
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_mget", response_body["method_id"]
    assert_equal conversation_customer_name.id, response_body.dig("variables", "customer_name", "id")
    assert_equal tone.id, response_body.dig("variables", "tone", "id")
    assert_nil response_body.dig("variables", "missing")

    get "/agent_api/conversation_variables",
      params: {
        workspace_id: context[:workspace].id,
        conversation_id: context[:conversation].id,
      },
      headers: agent_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_list", response_body["method_id"]
    assert_equal %w[customer_name tone], response_body["variables"].map { |variable| variable.fetch("key") }

    get "/agent_api/conversation_variables/resolve",
      params: {
        workspace_id: context[:workspace].id,
        conversation_id: context[:conversation].id,
      },
      headers: agent_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_resolve", response_body["method_id"]
    assert_equal "Acme China", response_body.dig("variables", "customer_name", "typed_value_payload", "value")
    assert_equal "gold", response_body.dig("variables", "support_tier", "typed_value_payload", "value")
  end

  test "write and promote endpoints materialize kernel owned canonical variable changes" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    post "/agent_api/conversation_variables/write",
      params: {
        workspace_id: context[:workspace].id,
        conversation_id: context[:conversation].id,
        key: "customer_name",
        typed_value_payload: { type: "string", value: "Acme China" },
        source_kind: "agent_runtime",
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :created
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_write", response_body["method_id"]
    assert_equal "conversation", response_body.dig("variable", "scope")

    conversation_variable = CanonicalVariable.find(response_body.dig("variable", "id"))
    assert_equal registration[:deployment], conversation_variable.writer

    post "/agent_api/conversation_variables/promote",
      params: {
        workspace_id: context[:workspace].id,
        conversation_id: context[:conversation].id,
        key: "customer_name",
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :created
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_promote", response_body["method_id"]
    assert_equal "workspace", response_body.dig("variable", "scope")
    assert_equal "Acme China", response_body.dig("variable", "typed_value_payload", "value")
  end
end
