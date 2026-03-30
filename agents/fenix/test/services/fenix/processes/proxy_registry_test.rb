require "test_helper"

class Fenix::Processes::ProxyRegistryTest < ActiveSupport::TestCase
  test "register writes a stable caddy routes fragment and lookup returns the route" do
    Dir.mktmpdir("fenix-proxy-registry-") do |tmpdir|
      routes_path = File.join(tmpdir, "routes.caddy")

      entry = Fenix::Processes::ProxyRegistry.new(routes_path: routes_path).register(
        process_run_id: "process-run-1",
        target_port: 4100
      )
      second_entry = Fenix::Processes::ProxyRegistry.new(routes_path: routes_path).register(
        process_run_id: "process-run-2",
        target_port: 4200
      )

      assert_equal "/dev/process-run-1", entry.fetch("path_prefix")
      assert_equal "http://127.0.0.1:4100", entry.fetch("target_url")
      assert_equal "/dev/process-run-2", second_entry.fetch("path_prefix")
      assert_equal entry, Fenix::Processes::ProxyRegistry.new(routes_path: routes_path).lookup(process_run_id: "process-run-1")
      assert_equal second_entry, Fenix::Processes::ProxyRegistry.new(routes_path: routes_path).lookup(process_run_id: "process-run-2")

      routes = File.read(routes_path)

      assert_includes routes, "handle_path /dev/process-run-1/*"
      assert_includes routes, "reverse_proxy 127.0.0.1:4100"
      assert_includes routes, "handle_path /dev/process-run-2/*"
      assert_includes routes, "reverse_proxy 127.0.0.1:4200"
    end
  end

  test "unregister removes the route from the rendered caddy fragment" do
    Dir.mktmpdir("fenix-proxy-registry-") do |tmpdir|
      routes_path = File.join(tmpdir, "routes.caddy")
      registry = Fenix::Processes::ProxyRegistry.new(routes_path: routes_path)

      registry.register(process_run_id: "process-run-1", target_port: 4100)
      registry.unregister(process_run_id: "process-run-1")

      assert_nil registry.lookup(process_run_id: "process-run-1")
      refute_includes File.read(routes_path), "process-run-1"
    end
  end
end
