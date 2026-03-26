require "test_helper"

class Variables::PromoteToWorkspaceTest < ActiveSupport::TestCase
  test "promotes a conversation store value into workspace scope and preserves superseded workspace history" do
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
    CanonicalStores::Set.call(
      conversation: context[:conversation],
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme China" },
    )

    promoted = Variables::PromoteToWorkspace.call(
      conversation: context[:conversation],
      key: "customer_name",
      writer: context[:user]
    )

    assert_equal "workspace", promoted.scope
    assert_equal "Acme China", promoted.typed_value_payload["value"]
    assert_equal context[:conversation], promoted.source_conversation
    assert_equal "promotion", promoted.source_kind
    assert_nil promoted.source_turn
    assert_nil promoted.source_workflow_run
    assert workspace_variable.reload.superseded?
    assert_equal promoted, workspace_variable.superseded_by
  end

  test "rejects promotion for archived conversations" do
    context = build_canonical_variable_context!
    CanonicalStores::Set.call(
      conversation: context[:conversation],
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme China" },
    )
    context[:conversation].update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Variables::PromoteToWorkspace.call(
        conversation: context[:conversation],
        key: "customer_name",
        writer: context[:user]
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before promotion"
  end
end
