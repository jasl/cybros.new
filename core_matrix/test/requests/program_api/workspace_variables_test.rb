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

    get "/program_api/workspace_variables/get",
      params: {
        workspace_id: context[:workspace].public_id,
        key: "support_tier",
      },
      headers: program_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "workspace_variables_get", response_body["method_id"]
    assert_equal context[:workspace].public_id, response_body["workspace_id"]
    refute response_body.fetch("variable").key?("id")
    assert_equal context[:workspace].public_id, response_body.dig("variable", "workspace_id")

    post "/program_api/workspace_variables/mget",
      params: {
        workspace_id: context[:workspace].public_id,
        keys: %w[support_tier region missing],
      },
      headers: program_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "workspace_variables_mget", response_body["method_id"]
    assert_equal context[:workspace].public_id, response_body["workspace_id"]
    refute response_body.dig("variables", "support_tier").key?("id")
    refute response_body.dig("variables", "region").key?("id")
    assert_nil response_body.dig("variables", "missing")

    get "/program_api/workspace_variables",
      params: {
        workspace_id: context[:workspace].public_id,
      },
      headers: program_api_headers(registration[:machine_credential])

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "workspace_variables_list", response_body["method_id"]
    assert_equal context[:workspace].public_id, response_body["workspace_id"]
    assert_equal %w[region support_tier], response_body["variables"].map { |variable| variable.fetch("key") }
    refute response_body["variables"].first.key?("id")
  end

  test "write endpoint materializes kernel owned workspace variables" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    post "/program_api/workspace_variables/write",
      params: {
        workspace_id: context[:workspace].public_id,
        key: "region",
        typed_value_payload: { type: "string", value: "cn" },
        source_kind: "agent_runtime",
        source_turn_id: context[:turn].public_id,
        source_workflow_run_id: context[:workflow_run].public_id,
      },
      headers: program_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :created

    response_body = JSON.parse(response.body)
    assert_equal "workspace_variables_write", response_body["method_id"]
    assert_equal "workspace", response_body.dig("variable", "scope")
    assert_equal "cn", response_body.dig("variable", "typed_value_payload", "value")
    refute response_body.fetch("variable").key?("id")

    variable = CanonicalVariable.find_by!(scope: "workspace", key: "region", current: true)
    assert_equal registration[:deployment], variable.writer
    assert_equal context[:turn], variable.source_turn
    assert_equal context[:workflow_run], variable.source_workflow_run
    refute_includes response.body, %("#{variable.id}")
  end

  test "write rejects raw bigint identifiers" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    post "/program_api/workspace_variables/write",
      params: {
        workspace_id: context[:workspace].id,
        key: "region",
        typed_value_payload: { type: "string", value: "cn" },
        source_kind: "agent_runtime",
      },
      headers: program_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :not_found

    post "/program_api/workspace_variables/write",
      params: {
        workspace_id: context[:workspace].public_id,
        key: "region",
        typed_value_payload: { type: "string", value: "cn" },
        source_kind: "agent_runtime",
        source_turn_id: context[:turn].id,
        source_workflow_run_id: context[:workflow_run].id,
      },
      headers: program_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :not_found
  end
end
