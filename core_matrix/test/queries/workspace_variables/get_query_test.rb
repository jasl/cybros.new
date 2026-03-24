require "test_helper"

module WorkspaceVariables
end

class WorkspaceVariables::GetQueryTest < ActiveSupport::TestCase
  test "returns the current workspace scoped value for a key" do
    context = build_canonical_variable_context!
    workspace_variable = Variables::Write.call(
      scope: "workspace",
      workspace: context[:workspace],
      key: "support_tier",
      typed_value_payload: { "type" => "string", "value" => "gold" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run]
    )

    assert_equal workspace_variable, WorkspaceVariables::GetQuery.call(
      workspace: context[:workspace],
      key: "support_tier"
    )
    assert_nil WorkspaceVariables::GetQuery.call(
      workspace: context[:workspace],
      key: "missing"
    )
  end
end
