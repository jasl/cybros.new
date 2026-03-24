require "test_helper"

module WorkspaceVariables
end

class WorkspaceVariables::ListQueryTest < ActiveSupport::TestCase
  test "returns current workspace scoped variables in key order" do
    context = build_canonical_variable_context!
    Variables::Write.call(
      scope: "workspace",
      workspace: context[:workspace],
      key: "support_tier",
      typed_value_payload: { "type" => "string", "value" => "silver" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run]
    )
    latest_support_tier = Variables::Write.call(
      scope: "workspace",
      workspace: context[:workspace],
      key: "support_tier",
      typed_value_payload: { "type" => "string", "value" => "gold" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run]
    )
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
    Variables::Write.call(
      scope: "conversation",
      workspace: context[:workspace],
      conversation: context[:conversation],
      key: "conversation_only",
      typed_value_payload: { "type" => "string", "value" => "direct" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run]
    )

    result = WorkspaceVariables::ListQuery.call(workspace: context[:workspace])

    assert_equal [region, latest_support_tier], result
  end
end
