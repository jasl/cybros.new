require "test_helper"

class CanonicalVariableFlowTest < ActionDispatch::IntegrationTest
  test "conversation store values override workspace values until explicitly promoted" do
    context = build_canonical_variable_context!

    workspace_variable = Variables::Write.call(
      scope: "workspace",
      workspace: context[:workspace],
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run],
      projection_policy: "silent"
    )
    LineageStores::Set.call(
      conversation: context[:conversation],
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme China" },
    )

    resolved = ConversationVariables::VisibleValuesResolver.call(
      workspace: context[:workspace],
      conversation: context[:conversation]
    )
    assert_equal "Acme China", resolved["customer_name"].typed_value_payload["value"]
    assert_equal workspace_variable, CanonicalVariable.effective_for(workspace: context[:workspace], key: "customer_name")

    promoted = Variables::PromoteToWorkspace.call(
      conversation: context[:conversation],
      key: "customer_name",
      writer: context[:user]
    )

    assert_equal "Acme China", promoted.typed_value_payload["value"]
    assert_equal promoted, CanonicalVariable.effective_for(workspace: context[:workspace], key: "customer_name")
    assert workspace_variable.reload.superseded?
    assert_equal 2, CanonicalVariable.where(key: "customer_name").count
  end
end
