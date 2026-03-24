require "test_helper"

class Variables::PromoteToWorkspaceTest < ActiveSupport::TestCase
  test "promotes a conversation value into workspace scope and preserves superseded workspace history" do
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

    promoted = Variables::PromoteToWorkspace.call(
      conversation_variable: conversation_variable,
      writer: context[:user]
    )

    assert_equal "workspace", promoted.scope
    assert_equal "Acme China", promoted.typed_value_payload["value"]
    assert_equal context[:conversation], promoted.source_conversation
    assert_equal "promotion", promoted.source_kind
    assert workspace_variable.reload.superseded?
    assert_equal promoted, workspace_variable.superseded_by
  end
end
