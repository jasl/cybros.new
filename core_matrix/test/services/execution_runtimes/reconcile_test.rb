require "test_helper"

module ExecutionRuntimes
  class ReconcileTest < ActiveSupport::TestCase
    test "reuses the same execution runtime for a stable installation-local fingerprint" do
      installation = create_installation!
      existing = create_execution_runtime!(
        installation: installation,
        kind: "local",
        runtime_fingerprint: "fenix-host-a",
        connection_metadata: {
          "transport" => "http",
          "base_url" => "https://fenix-v1.example.test",
        }
      )

      reconciled = ExecutionRuntimes::Reconcile.call(
        installation: installation,
        runtime_fingerprint: "fenix-host-a",
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

    test "rejects blank runtime fingerprints" do
      error = assert_raises(ExecutionRuntimes::Reconcile::MissingRuntimeFingerprint) do
        ExecutionRuntimes::Reconcile.call(
          installation: create_installation!,
          runtime_fingerprint: "   ",
          kind: "local",
          connection_metadata: {}
        )
      end

      assert_equal "runtime fingerprint must be provided", error.message
    end
  end
end
