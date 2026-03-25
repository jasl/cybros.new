require "test_helper"

class CanonicalVariableTest < ActiveSupport::TestCase
  test "enforces workspace-only scope and supersession history fields" do
    context = build_canonical_variable_context!

    workspace_variable = CanonicalVariable.new(
      installation: context[:installation],
      workspace: context[:workspace],
      scope: "workspace",
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme" },
      writer: context[:user],
      source_kind: "manual_user",
      source_conversation: context[:conversation],
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run],
      projection_policy: "silent",
      current: true
    )

    assert workspace_variable.valid?

    invalid_workspace_scope = workspace_variable.dup
    invalid_workspace_scope.scope = "conversation"
    assert_not invalid_workspace_scope.valid?
    assert_includes invalid_workspace_scope.errors[:scope], "must be workspace"

    superseded = workspace_variable.dup
    superseded.current = false
    assert_not superseded.valid?
    assert_includes superseded.errors[:superseded_at], "must exist once a canonical variable is superseded"
    assert_includes superseded.errors[:superseded_by], "must exist once a canonical variable is superseded"
  end
end
