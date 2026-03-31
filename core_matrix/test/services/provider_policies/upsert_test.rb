require "test_helper"

class ProviderPolicies::UpsertTest < ActiveSupport::TestCase
  test "creates and updates provider policies through an audited service boundary" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")

    policy = ProviderPolicies::Upsert.call(
      installation: installation,
      actor: actor,
      provider_handle: "openai",
      enabled: true,
      selection_defaults: { "interactive" => "role:main" }
    )

    updated = ProviderPolicies::Upsert.call(
      installation: installation,
      actor: actor,
      provider_handle: "openai",
      enabled: false,
      selection_defaults: { "interactive" => "candidate:openai/gpt-5.3-chat-latest" }
    )

    assert_equal policy.id, updated.id
    assert_equal 1, ProviderPolicy.count
    assert_not updated.enabled?
    assert_equal({ "interactive" => "candidate:openai/gpt-5.3-chat-latest" }, updated.selection_defaults)

    assert_equal 2, AuditLog.where(action: "provider_policy.upserted").count
  end

  test "rejects unknown provider handles at the service boundary" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      ProviderPolicies::Upsert.call(
        installation: installation,
        actor: actor,
        provider_handle: "unknown_provider",
        enabled: true,
        selection_defaults: {}
      )
    end

    assert_includes error.record.errors[:provider_handle], "must exist in the provider catalog"
  end
end
