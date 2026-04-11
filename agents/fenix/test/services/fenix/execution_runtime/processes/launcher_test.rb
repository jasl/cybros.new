require "test_helper"

class FenixProcessesLauncherTest < ActiveSupport::TestCase
  test "launch! spawns the process and registers a proxy route when proxy_port is provided" do
    spawned = nil
    registered = nil
    environment = { "HELLO" => "workspace" }

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

    result = Fenix::ExecutionRuntime::Processes::Launcher.call(
      process_run: {
        "process_run_id" => "process-run-1",
        "runtime_owner_id" => "task-1",
      },
      command_line: "bin/dev",
      proxy_port: 4100,
      environment: environment,
      manager: manager,
      proxy_registry: proxy_registry
    )

    assert_equal "process-run-1", spawned.fetch(:process_run_id)
    assert_equal "task-1", spawned.fetch(:runtime_owner_id)
    assert_equal "bin/dev", spawned.fetch(:command_line)
    assert_equal environment, spawned.fetch(:environment)
    assert_equal "process-run-1", registered.fetch(:process_run_id)
    assert_equal 4100, registered.fetch(:target_port)
    assert_equal "/dev/process-run-1", result.fetch("proxy_path")
    assert_equal "http://127.0.0.1:4100", result.fetch("proxy_target_url")
  end
end
