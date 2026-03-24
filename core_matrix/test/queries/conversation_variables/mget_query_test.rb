require "test_helper"

module ConversationVariables
end

class ConversationVariables::MgetQueryTest < ActiveSupport::TestCase
  test "returns current conversation scoped values keyed by the requested names" do
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

    result = ConversationVariables::MgetQuery.call(
      workspace: context[:workspace],
      conversation: context[:conversation],
      keys: %w[customer_name tone workspace_only missing]
    )

    assert_equal latest_customer_name, result["customer_name"]
    assert_equal tone, result["tone"]
    assert_nil result["workspace_only"]
    assert_nil result["missing"]
  end
end
