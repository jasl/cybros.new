require "test_helper"

class Conversations::UpdateOverrideTest < ActiveSupport::TestCase
  test "persists subagent policy override payload and auto selector state" do
    conversation = create_profile_aware_conversation!

    updated = Conversations::UpdateOverride.call(
      conversation: conversation,
      payload: { "subagents" => { "enabled" => false } },
      schema_fingerprint: "schema-v1",
      reconciliation_report: { "status" => "exact" },
      selector_mode: "auto"
    )

    assert_equal({ "subagents" => { "enabled" => false } }, updated.override_payload)
    assert_equal "schema-v1", updated.override_last_schema_fingerprint
    assert_equal({ "status" => "exact" }, updated.override_reconciliation_report)
    assert_equal "auto", updated.interactive_selector_mode
    assert_nil updated.interactive_selector_provider_handle
    assert_nil updated.interactive_selector_model_ref
    assert_not_nil updated.override_updated_at
  end

  test "persists an explicit candidate selector" do
    conversation = create_profile_aware_conversation!

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

  test "rejects an explicit selector with an unknown provider" do
    conversation = create_profile_aware_conversation!

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::UpdateOverride.call(
        conversation: conversation,
        payload: {},
        schema_fingerprint: "schema-v1",
        selector_mode: "explicit_candidate",
        selector_provider_handle: "unknown_provider",
        selector_model_ref: "gpt-5.4"
      )
    end

    assert_includes error.record.errors[:interactive_selector_provider_handle], "must exist in the provider catalog"
  end

  test "rejects an explicit selector with an unknown model" do
    conversation = create_profile_aware_conversation!

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::UpdateOverride.call(
        conversation: conversation,
        payload: {},
        schema_fingerprint: "schema-v1",
        selector_mode: "explicit_candidate",
        selector_provider_handle: "codex_subscription",
        selector_model_ref: "unknown_model"
      )
    end

    assert_includes error.record.errors[:interactive_selector_model_ref], "must exist in the provider catalog"
  end

  test "rejects override updates for archived conversations" do
    conversation = create_profile_aware_conversation!
    conversation.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::UpdateOverride.call(
        conversation: conversation,
        payload: { "subagents" => { "enabled" => false } },
        schema_fingerprint: "schema-v1",
        reconciliation_report: { "status" => "exact" },
        selector_mode: "auto"
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before updating overrides"
  end

  test "rejects override updates for pending delete conversations" do
    conversation = create_profile_aware_conversation!
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::UpdateOverride.call(
        conversation: conversation,
        payload: { "subagents" => { "enabled" => false } },
        schema_fingerprint: "schema-v1",
        reconciliation_report: { "status" => "exact" },
        selector_mode: "auto"
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before updating overrides"
  end

  test "rejects override updates while close is in progress" do
    conversation = create_profile_aware_conversation!
    ConversationCloseOperation.create!(
      installation: conversation.installation,
      conversation: conversation,
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::UpdateOverride.call(
        conversation: conversation,
        payload: { "subagents" => { "enabled" => false } },
        schema_fingerprint: "schema-v1",
        reconciliation_report: { "status" => "exact" },
        selector_mode: "auto"
      )
    end

    assert_includes error.record.errors[:base], "must not update overrides while close is in progress"
  end

  private

  def create_profile_aware_conversation!
    registration = register_agent_runtime!(
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
    workspace = create_workspace!(
      installation: registration[:installation],
      user: registration[:actor],
      user_program_binding: create_user_program_binding!(
        installation: registration[:installation],
        user: registration[:actor],
        agent_program: registration[:agent_program]
      )
    )

    Conversations::CreateRoot.call(
      workspace: workspace,
      executor_program: registration[:executor_program],
      agent_program_version: registration[:deployment]
    )
  end
end
