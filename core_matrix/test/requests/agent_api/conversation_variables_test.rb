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
    refute response_body.fetch("variable").key?("id")
    assert_equal context[:workspace].public_id, response_body.dig("variable", "workspace_id")
    assert_equal context[:conversation].public_id, response_body.dig("variable", "conversation_id")

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

    get "/agent_api/conversation_variables",
      params: {
        workspace_id: context[:workspace].public_id,
        conversation_id: context[:conversation].public_id,
      },
      headers: agent_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_list", response_body["method_id"]
    assert_equal context[:workspace].public_id, response_body["workspace_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    assert_equal %w[customer_name tone], response_body["variables"].map { |variable| variable.fetch("key") }
    refute response_body["variables"].first.key?("id")

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

  test "write and promote endpoints materialize kernel owned canonical variable changes" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    post "/agent_api/conversation_variables/write",
      params: {
        workspace_id: context[:workspace].public_id,
        conversation_id: context[:conversation].public_id,
        key: "customer_name",
        typed_value_payload: { type: "string", value: "Acme China" },
        source_kind: "agent_runtime",
        source_turn_id: context[:turn].public_id,
        source_workflow_run_id: context[:workflow_run].public_id,
      },
      headers: agent_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :created
    response_body = JSON.parse(response.body)
    assert_equal "conversation_variables_write", response_body["method_id"]
    assert_equal "conversation", response_body.dig("variable", "scope")
    refute response_body.fetch("variable").key?("id")

    conversation_variable = CanonicalVariable.find_by!(scope: "conversation", key: "customer_name", current: true)
    assert_equal registration[:deployment], conversation_variable.writer
    assert_equal context[:turn], conversation_variable.source_turn
    assert_equal context[:workflow_run], conversation_variable.source_workflow_run

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
    refute_includes response.body, %("#{conversation_variable.id}")
  end
end
