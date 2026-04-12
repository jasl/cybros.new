require "test_helper"

module ExecutionRuntimes
  class ReconcileTest < ActiveSupport::TestCase
    test "reuses the same execution runtime when the active runtime version keeps the same fingerprint" do
      installation = create_installation!
      existing = create_execution_runtime!(
        installation: installation,
        kind: "local"
      )
      existing_version = create_execution_runtime_version!(
        installation: installation,
        execution_runtime: existing,
        execution_runtime_fingerprint: "fenix-host-a"
      )
      existing.update!(
        active_execution_runtime_version: existing_version
      )

      reconciled = ExecutionRuntimes::Reconcile.call(
        installation: installation,
        execution_runtime_fingerprint: "fenix-host-a",
        kind: "container",
        connection_metadata: {
          "transport" => "http",
          "base_url" => "https://fenix-v2.example.test",
        }
      )

      assert_equal existing, reconciled
      assert_equal "container", reconciled.kind
      assert_equal existing_version, reconciled.active_execution_runtime_version
      assert_equal "fenix-host-a", reconciled.execution_runtime_fingerprint
    end

    test "creates a new execution runtime when no active runtime version matches the fingerprint yet" do
      installation = create_installation!

      assert_difference("ExecutionRuntime.count", 1) do
        reconciled = ExecutionRuntimes::Reconcile.call(
          installation: installation,
          execution_runtime_fingerprint: "fresh-runtime-host",
          kind: "remote",
          connection_metadata: {
            "transport" => "http",
            "base_url" => "https://fresh-runtime.example.test",
          }
        )

        assert_equal installation, reconciled.installation
        assert_equal "remote", reconciled.kind
        assert_equal "fresh-runtime-host", reconciled.display_name
      end
    end

    test "rejects blank execution runtime fingerprints" do
      error = assert_raises(ExecutionRuntimes::Reconcile::MissingExecutionRuntimeFingerprint) do
        ExecutionRuntimes::Reconcile.call(
          installation: create_installation!,
          execution_runtime_fingerprint: "   ",
          kind: "local",
          connection_metadata: {}
        )
      end

      assert_equal "execution runtime fingerprint must be provided", error.message
    end
  end
end
