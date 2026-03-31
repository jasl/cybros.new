require "test_helper"

class RuntimeTopology::CoreMatrixTest < ActiveSupport::TestCase
  self.uses_real_provider_catalog = true

  test "defines llm queues for every provider in the catalog" do
    topology = RuntimeTopology::CoreMatrix.load
    topology_handles = topology.fetch("llm_queues").keys.sort
    catalog_handles = ProviderCatalog::Registry.current.providers.keys.sort

    assert_equal catalog_handles, topology_handles
  end

  test "resolves provider and shared queue names from the checked-in topology" do
    assert_equal "llm_openai", RuntimeTopology::CoreMatrix.llm_queue_name("openai")
    assert_equal "tool_calls", RuntimeTopology::CoreMatrix.shared_queue_name("tool_calls")
    assert_equal "workflow_default", RuntimeTopology::CoreMatrix.shared_queue_name("workflow_default")
  end
end
