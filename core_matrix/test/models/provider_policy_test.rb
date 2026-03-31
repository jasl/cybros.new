require "test_helper"

class ProviderPolicyTest < ActiveSupport::TestCase
  test "supports enablement and selection defaults" do
    policy = ProviderPolicy.create!(
      installation: create_installation!,
      provider_handle: "openai",
      enabled: false,
      selection_defaults: { "interactive" => "role:main" }
    )

    assert_not policy.enabled?
    assert_equal({ "interactive" => "role:main" }, policy.selection_defaults)
  end

  test "does not validate provider handle membership in the static catalog" do
    policy = ProviderPolicy.new(
      installation: create_installation!,
      provider_handle: "unknown_provider",
      enabled: true,
      selection_defaults: {}
    )

    assert policy.valid?
  end
end
