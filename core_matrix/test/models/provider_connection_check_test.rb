require "test_helper"

class ProviderConnectionCheckTest < ActiveSupport::TestCase
  test "requires one latest record per installation and provider" do
    installation = create_installation!

    ProviderConnectionCheck.create!(
      installation: installation,
      provider_handle: "openai",
      lifecycle_state: "queued",
      queued_at: Time.current,
      request_payload: {},
      result_payload: {},
      failure_payload: {}
    )

    duplicate = ProviderConnectionCheck.new(
      installation: installation,
      provider_handle: "openai",
      lifecycle_state: "queued",
      queued_at: Time.current,
      request_payload: {},
      result_payload: {},
      failure_payload: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:provider_handle], "has already been taken"
  end
end
