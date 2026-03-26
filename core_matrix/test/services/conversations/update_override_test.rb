require "test_helper"

class Conversations::UpdateOverrideTest < ActiveSupport::TestCase
  test "persists override payload and auto selector state" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    updated = Conversations::UpdateOverride.call(
      conversation: conversation,
      payload: { "temperature" => 0.2 },
      schema_fingerprint: "schema-v1",
      reconciliation_report: { "status" => "exact" },
      selector_mode: "auto"
    )

    assert_equal({ "temperature" => 0.2 }, updated.override_payload)
    assert_equal "schema-v1", updated.override_last_schema_fingerprint
    assert_equal({ "status" => "exact" }, updated.override_reconciliation_report)
    assert_equal "auto", updated.interactive_selector_mode
    assert_nil updated.interactive_selector_provider_handle
    assert_nil updated.interactive_selector_model_ref
    assert_not_nil updated.override_updated_at
  end

  test "persists an explicit candidate selector" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )

    updated = Conversations::UpdateOverride.call(
      conversation: conversation,
      payload: {},
      schema_fingerprint: "schema-v1",
      selector_mode: "explicit_candidate",
      selector_provider_handle: "codex_subscription",
      selector_model_ref: "gpt-5.4"
    )

    assert_equal "explicit_candidate", updated.interactive_selector_mode
    assert_equal "codex_subscription", updated.interactive_selector_provider_handle
    assert_equal "gpt-5.4", updated.interactive_selector_model_ref
  end
end
