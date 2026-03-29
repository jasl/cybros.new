require "test_helper"

class DummyAgentRuntimeTest < ActiveSupport::TestCase
  test "register payload includes a stable environment fingerprint for registration pairing" do
    load_dummy_agent_runtime_class!

    payload =
      with_modified_env(
        "CORE_MATRIX_ENROLLMENT_TOKEN" => "manual-enrollment-token",
        "CORE_MATRIX_ENVIRONMENT_FINGERPRINT" => "dummy-host-a",
      ) do
        DummyAgentRuntime.new(["register"]).send(:register_payload)
      end

    assert_equal "dummy-host-a", payload["environment_fingerprint"]
    refute payload.key?("execution_environment_id")
  end

  private

  def load_dummy_agent_runtime_class!
    return if Object.const_defined?(:DummyAgentRuntime)

    load Rails.root.join("script/manual/dummy_agent_runtime.rb")
  end

  def with_modified_env(overrides)
    original_values = overrides.transform_values { |_, _| nil }

    overrides.each_key do |key|
      original_values[key] = ENV[key]
    end

    overrides.each do |key, value|
      ENV[key] = value
    end

    yield
  ensure
    original_values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
