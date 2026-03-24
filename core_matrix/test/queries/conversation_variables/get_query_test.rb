require "test_helper"

module ConversationVariables
end

class ConversationVariables::GetQueryTest < ActiveSupport::TestCase
  test "returns only the current conversation scoped value for a key" do
    context = build_canonical_variable_context!
    Variables::Write.call(
      scope: "workspace",
      workspace: context[:workspace],
      key: "workspace_only",
      typed_value_payload: { "type" => "string", "value" => "Workspace" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run]
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
      source_workflow_run: context[:workflow_run]
    )

    assert_equal conversation_variable, ConversationVariables::GetQuery.call(
      workspace: context[:workspace],
      conversation: context[:conversation],
      key: "customer_name"
    )
    assert_nil ConversationVariables::GetQuery.call(
      workspace: context[:workspace],
      conversation: context[:conversation],
      key: "workspace_only"
    )
  end
end
