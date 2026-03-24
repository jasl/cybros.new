require "test_helper"

module ConversationVariables
end

class ConversationVariables::ListQueryTest < ActiveSupport::TestCase
  test "returns current conversation scoped variables without workspace fallback rows" do
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
    Variables::Write.call(
      scope: "conversation",
      workspace: context[:workspace],
      conversation: context[:conversation],
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run]
    )
    latest_customer_name = Variables::Write.call(
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

    result = ConversationVariables::ListQuery.call(
      workspace: context[:workspace],
      conversation: context[:conversation]
    )

    assert_equal [latest_customer_name, tone], result
  end
end
