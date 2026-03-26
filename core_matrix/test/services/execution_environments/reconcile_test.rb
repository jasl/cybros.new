require "test_helper"

module ExecutionEnvironments
  class ReconcileTest < ActiveSupport::TestCase
    test "reuses the same execution environment for a stable installation-local fingerprint" do
      installation = create_installation!
      existing = create_execution_environment!(
        installation: installation,
        kind: "local",
        environment_fingerprint: "fenix-host-a",
        connection_metadata: {
          "transport" => "http",
          "base_url" => "https://fenix-v1.example.test",
        }
      )

      reconciled = ExecutionEnvironments::Reconcile.call(
        installation: installation,
        environment_fingerprint: "fenix-host-a",
        kind: "container",
        connection_metadata: {
          "transport" => "http",
          "base_url" => "https://fenix-v2.example.test",
        }
      )

      assert_equal existing, reconciled
      assert_equal "container", reconciled.kind
      assert_equal "https://fenix-v2.example.test", reconciled.connection_metadata["base_url"]
    end

    test "rejects blank environment fingerprints" do
      error = assert_raises(ExecutionEnvironments::Reconcile::MissingEnvironmentFingerprint) do
        ExecutionEnvironments::Reconcile.call(
          installation: create_installation!,
          environment_fingerprint: "   ",
          kind: "local",
          connection_metadata: {}
        )
      end

      assert_equal "environment fingerprint must be provided", error.message
    end
  end
end
