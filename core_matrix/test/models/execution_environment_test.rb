require "test_helper"

class ExecutionEnvironmentTest < ActiveSupport::TestCase
  test "tracks kind and connection metadata" do
    installation = create_installation!
    environment = create_execution_environment!(
      installation: installation,
      kind: "container",
      connection_metadata: {
        "transport" => "http",
        "base_url" => "https://agents.example.test",
      }
    )

    assert environment.container?
    assert_equal "https://agents.example.test", environment.connection_metadata["base_url"]

    invalid_environment = ExecutionEnvironment.new(
      installation: installation,
      kind: "local",
      connection_metadata: []
    )

    assert_not invalid_environment.valid?
    assert_includes invalid_environment.errors[:connection_metadata], "must be a Hash"
  end
end
