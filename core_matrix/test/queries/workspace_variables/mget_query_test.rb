require "test_helper"

module WorkspaceVariables
end

class WorkspaceVariables::MgetQueryTest < ActiveSupport::TestCase
  test "returns current workspace scoped values keyed by the requested names" do
    context = build_canonical_variable_context!
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

    result = WorkspaceVariables::MgetQuery.call(
      workspace: context[:workspace],
      keys: %w[support_tier region missing]
    )

    assert_equal support_tier, result["support_tier"]
    assert_equal region, result["region"]
    assert_nil result["missing"]
  end
end
