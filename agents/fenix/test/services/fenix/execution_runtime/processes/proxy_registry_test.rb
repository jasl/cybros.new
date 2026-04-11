require "test_helper"

class FenixProcessesProxyRegistryTest < ActiveSupport::TestCase
  teardown do
    Fenix::ExecutionRuntime::Processes::ProxyRegistry.reset_default!
  end

  test "register writes a stable caddy routes fragment and lookup returns the route" do
    Dir.mktmpdir("fenix-proxy-registry-") do |tmpdir|
      routes_path = File.join(tmpdir, "routes.caddy")

      entry = Fenix::ExecutionRuntime::Processes::ProxyRegistry.new(routes_path: routes_path).register(
        process_run_id: "process-run-1",
        target_port: 4100
      )
      second_entry = Fenix::ExecutionRuntime::Processes::ProxyRegistry.new(routes_path: routes_path).register(
        process_run_id: "process-run-2",
        target_port: 4200
      )

      assert_equal "/dev/process-run-1", entry.fetch("path_prefix")
      assert_equal "http://127.0.0.1:4100", entry.fetch("target_url")
      assert_equal entry, Fenix::ExecutionRuntime::Processes::ProxyRegistry.new(routes_path: routes_path).lookup(process_run_id: "process-run-1")
      assert_equal second_entry, Fenix::ExecutionRuntime::Processes::ProxyRegistry.new(routes_path: routes_path).lookup(process_run_id: "process-run-2")

      routes = File.read(routes_path)

      assert_includes routes, "handle_path /dev/process-run-1/*"
      assert_includes routes, "reverse_proxy 127.0.0.1:4100"
      assert_includes routes, "handle_path /dev/process-run-2/*"
      assert_includes routes, "reverse_proxy 127.0.0.1:4200"
    end
  end
end
