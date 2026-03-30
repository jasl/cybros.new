require "test_helper"

class Fenix::Processes::LauncherTest < ActiveSupport::TestCase
  test "launch! spawns the process and registers a proxy route when proxy_port is provided" do
    spawned = nil
    registered = nil

    manager = Module.new do
      define_singleton_method(:spawn!) do |**kwargs|
        spawned = kwargs
      end
    end

    proxy_registry = Module.new do
      define_singleton_method(:register) do |**kwargs|
        registered = kwargs
        {
          "process_run_id" => kwargs.fetch(:process_run_id),
          "path_prefix" => "/dev/#{kwargs.fetch(:process_run_id)}",
          "target_url" => "http://127.0.0.1:#{kwargs.fetch(:target_port)}",
        }
      end
    end

    result = Fenix::Processes::Launcher.call(
      process_run: {
        "process_run_id" => "process-run-1",
      },
      command_line: "bin/dev",
      proxy_port: 4100,
      manager: manager,
      proxy_registry: proxy_registry
    )

    assert_equal "process-run-1", spawned.fetch(:process_run_id)
    assert_equal "bin/dev", spawned.fetch(:command_line)
    assert_equal "process-run-1", registered.fetch(:process_run_id)
    assert_equal 4100, registered.fetch(:target_port)
    assert_equal "/dev/process-run-1", result.fetch("proxy_path")
    assert_equal "http://127.0.0.1:4100", result.fetch("proxy_target_url")
  end

  test "launch! skips proxy registration when proxy_port is omitted" do
    spawned = nil

    manager = Module.new do
      define_singleton_method(:spawn!) do |**kwargs|
        spawned = kwargs
      end
    end

    proxy_registry = Module.new do
      define_singleton_method(:register) do |**|
        raise "proxy registry should not be called"
      end
    end

    result = Fenix::Processes::Launcher.call(
      process_run: {
        "process_run_id" => "process-run-2",
      },
      command_line: "bin/dev",
      manager: manager,
      proxy_registry: proxy_registry
    )

    assert_equal "process-run-2", spawned.fetch(:process_run_id)
    assert_equal "running", result.fetch("lifecycle_state")
    assert_nil result["proxy_path"]
  end
end
