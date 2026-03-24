require "test_helper"

class Variables::WriteTest < ActiveSupport::TestCase
  test "supersedes prior current values while preserving conversation history" do
    context = build_canonical_variable_context!

    first = Variables::Write.call(
      scope: "conversation",
      workspace: context[:workspace],
      conversation: context[:conversation],
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run],
      projection_policy: "silent"
    )
    second = Variables::Write.call(
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

    assert first.reload.superseded?
    assert_equal second, first.superseded_by
    assert_equal "Acme China", second.typed_value_payload["value"]
    assert_equal second, CanonicalVariable.effective_for(
      workspace: context[:workspace],
      conversation: context[:conversation],
      key: "customer_name"
    )
    assert_equal [first.id, second.id], CanonicalVariable.where(scope: "conversation", key: "customer_name").order(:created_at).pluck(:id)
  end
end
