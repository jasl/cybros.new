require "test_helper"

class ProviderExecution::WithProviderRequestLeaseTest < ActiveSupport::TestCase
  WorkflowRunDouble = Struct.new(:installation, keyword_init: true)
  RequestContextDouble = Struct.new(:provider_handle, keyword_init: true)

  class FakeGovernor
    class << self
      attr_accessor :acquire_calls, :renew_calls, :release_calls

      def reset!
        self.acquire_calls = []
        self.renew_calls = []
        self.release_calls = []
      end

      def acquire(**kwargs)
        acquire_calls << kwargs
        ProviderExecution::ProviderRequestGovernor::Decision.new(
          allowed: true,
          provider_handle: kwargs.fetch(:provider_handle),
          reason: nil,
          retry_at: nil,
          lease_token: "lease-123",
          lease_expires_at: Time.current + 1.second
        )
      end

      def renew(**kwargs)
        renew_calls << kwargs
      end

      def release(**kwargs)
        release_calls << kwargs
      end

      def record_rate_limit!(**)
        raise "not expected in this test"
      end
    end
  end

  setup do
    FakeGovernor.reset!
  end

  test "renews the lease while the wrapped request is still running" do
    workflow_run = WorkflowRunDouble.new(installation: create_installation!)
    request_context = RequestContextDouble.new(provider_handle: "openai")

    result = ProviderExecution::WithProviderRequestLease.new(
      workflow_run: workflow_run,
      request_context: request_context,
      effective_catalog: ProviderCatalog::EffectiveCatalog.new(installation: workflow_run.installation),
      governor: FakeGovernor,
      lease_renew_interval_seconds: 0.01
    ).call do
      sleep 0.03
      :ok
    end

    assert_equal :ok, result
    assert_operator FakeGovernor.renew_calls.length, :>=, 1
    assert_equal "lease-123", FakeGovernor.release_calls.last.fetch(:lease_token)
  end
end
