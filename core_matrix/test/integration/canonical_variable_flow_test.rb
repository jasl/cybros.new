require "test_helper"

class CanonicalVariableFlowTest < ActionDispatch::IntegrationTest
  test "conversation variables override workspace values until explicitly promoted" do
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
    conversation_variable = Variables::Write.call(
      scope: "conversation",
      workspace: context[:workspace],
      conversation: context[:conversation],
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme China" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run],
      projection_policy: "silent"
    )

    assert_equal conversation_variable, CanonicalVariable.effective_for(
      workspace: context[:workspace],
      conversation: context[:conversation],
      key: "customer_name"
    )
    assert_equal workspace_variable, CanonicalVariable.effective_for(
      workspace: context[:workspace],
      key: "customer_name"
    )

    promoted = Variables::PromoteToWorkspace.call(
      conversation_variable: conversation_variable,
      writer: context[:user]
    )

    assert_equal "Acme China", promoted.typed_value_payload["value"]
    assert_equal promoted, CanonicalVariable.effective_for(
      workspace: context[:workspace],
      key: "customer_name"
    )
    assert conversation_variable.reload.current?
    assert workspace_variable.reload.superseded?
    assert_equal 3, CanonicalVariable.where(key: "customer_name").count
  end
end
