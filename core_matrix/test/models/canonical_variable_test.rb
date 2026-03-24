require "test_helper"

class CanonicalVariableTest < ActiveSupport::TestCase
  test "enforces workspace and conversation scope rules and supersession history fields" do
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
    conversation_variable = CanonicalVariable.new(
      installation: context[:installation],
      workspace: context[:workspace],
      conversation: context[:conversation],
      scope: "conversation",
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme China" },
      writer: context[:user],
      source_kind: "manual_user",
      source_conversation: context[:conversation],
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run],
      projection_policy: "silent",
      current: true
    )

    assert workspace_variable.valid?
    assert conversation_variable.valid?

    invalid_workspace_scope = workspace_variable.dup
    invalid_workspace_scope.conversation = context[:conversation]
    assert_not invalid_workspace_scope.valid?
    assert_includes invalid_workspace_scope.errors[:conversation], "must be blank for workspace scope"

    invalid_conversation_scope = conversation_variable.dup
    invalid_conversation_scope.conversation = nil
    assert_not invalid_conversation_scope.valid?
    assert_includes invalid_conversation_scope.errors[:conversation], "must exist for conversation scope"

    superseded = conversation_variable.dup
    superseded.current = false
    assert_not superseded.valid?
    assert_includes superseded.errors[:superseded_at], "must exist once a canonical variable is superseded"
    assert_includes superseded.errors[:superseded_by], "must exist once a canonical variable is superseded"
  end
end
