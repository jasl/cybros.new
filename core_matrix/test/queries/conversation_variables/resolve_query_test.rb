require "test_helper"

module ConversationVariables
end

class ConversationVariables::ResolveQueryTest < ActiveSupport::TestCase
  test "returns the effective merged view with conversation values overriding workspace defaults" do
    context = build_canonical_variable_context!
    workspace_customer_name = Variables::Write.call(
      scope: "workspace",
      workspace: context[:workspace],
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme" },
      writer: context[:user],
      source_kind: "manual_user",
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run]
    )
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
    conversation_customer_name = Variables::Write.call(
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

    result = ConversationVariables::ResolveQuery.call(
      workspace: context[:workspace],
      conversation: context[:conversation]
    )

    assert_equal conversation_customer_name, result["customer_name"]
    assert_equal support_tier, result["support_tier"]
    assert_equal tone, result["tone"]
    refute_equal workspace_customer_name, result["customer_name"]
  end
end
