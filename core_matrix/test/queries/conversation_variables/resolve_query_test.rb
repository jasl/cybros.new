require "test_helper"

module ConversationVariables
end

class ConversationVariables::ResolveQueryTest < ActiveSupport::TestCase
  test "returns the effective merged view with conversation values overriding workspace defaults" do
    context = build_canonical_variable_context!
    Variables::Write.call(
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
    CanonicalStores::Set.call(
      conversation: context[:conversation],
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme China" },
    )
    CanonicalStores::Set.call(
      conversation: context[:conversation],
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" },
    )

    result = ConversationVariables::ResolveQuery.call(
      workspace: context[:workspace],
      conversation: context[:conversation]
    )

    assert_equal "Acme China", result["customer_name"].typed_value_payload["value"]
    assert_equal support_tier, result["support_tier"]
    assert_equal "direct", result["tone"].typed_value_payload["value"]
  end
end
