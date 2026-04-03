require "test_helper"
require Rails.root.join("script/manual/manual_acceptance_support")
require "tmpdir"

class ManualAcceptanceSupportTest < ActiveSupport::TestCase
  ExecutionSnapshot = Struct.new(:conversation_projection)
  WorkflowRunDouble = Struct.new(:execution_snapshot)

  test "execute_provider_workflow! uses a provider-backed timeout that fits real acceptance runs" do
    workflow_run = WorkflowRunDouble.new(ExecutionSnapshot.new({ "messages" => [] }))
    captured_timeout = nil

    with_redefined_singleton_method(Workflows::ExecuteRun, :call, ->(*) { nil }) do
      with_redefined_singleton_method(
        ManualAcceptanceSupport,
        :wait_for_workflow_run_terminal!,
        ->(workflow_run:, timeout_seconds:, poll_interval_seconds: 0.1) { captured_timeout = timeout_seconds }
      ) do
        ManualAcceptanceSupport.execute_provider_workflow!(workflow_run:)
      end
    end

    assert_equal 3_600, captured_timeout
  end

  test "execute_provider_workflow! still honors an explicit timeout override" do
    workflow_run = WorkflowRunDouble.new(ExecutionSnapshot.new({ "messages" => [] }))
    captured_timeout = nil

    with_redefined_singleton_method(Workflows::ExecuteRun, :call, ->(*) { nil }) do
      with_redefined_singleton_method(
        ManualAcceptanceSupport,
        :wait_for_workflow_run_terminal!,
        ->(workflow_run:, timeout_seconds:, poll_interval_seconds: 0.1) { captured_timeout = timeout_seconds }
      ) do
        ManualAcceptanceSupport.execute_provider_workflow!(workflow_run:, timeout_seconds: 42)
      end
    end

    assert_equal 42, captured_timeout
  end

  test "reset_backend_state! includes conversation diagnostics snapshots" do
    assert_includes ManualAcceptanceSupport::RESET_MODELS, TurnDiagnosticsSnapshot
    assert_includes ManualAcceptanceSupport::RESET_MODELS, ConversationDiagnosticsSnapshot
  end

  test "reset_docker_fenix_runtime_database! syncs source and performs a destructive runtime db reset" do
    sync_container = nil
    capture3_args = nil
    success_status = stub_process_status(success: true)

    with_redefined_singleton_method(
      ManualAcceptanceSupport,
      :sync_fenix_runtime_source_to_docker_container!,
      ->(container_name:) { sync_container = container_name }
    ) do
      with_redefined_singleton_method(
        Open3,
        :capture3,
        ->(*args) { capture3_args = args; ["ok", "", success_status] }
      ) do
        result = ManualAcceptanceSupport.reset_docker_fenix_runtime_database!(container_name: "fenix-capstone")

        assert_equal "fenix-capstone", sync_container
        assert_equal [
          "docker", "exec", "fenix-capstone", "sh", "-lc",
          "cd /rails && export RAILS_ENV=production DISABLE_DATABASE_ENVIRONMENT_CHECK=1 && (bin/rails db:drop || true) && bin/rails db:create && bin/rails db:migrate && bin/rails db:seed",
        ], capture3_args
        assert_equal(
          "docker exec fenix-capstone sh -lc cd /rails && export RAILS_ENV=production DISABLE_DATABASE_ENVIRONMENT_CHECK=1 && (bin/rails db:drop || true) && bin/rails db:create && bin/rails db:migrate && bin/rails db:seed",
          result.fetch("command")
        )
        assert_equal "ok", result.fetch("stdout")
        assert_equal "", result.fetch("stderr")
        assert_equal true, result.fetch("success")
      end
    end
  end

  test "sync_fenix_runtime_source_to_docker_container! clears docker targets before copying without a shell command" do
    capture3_calls = []
    success_status = stub_process_status(success: true)

    Dir.mktmpdir do |tmpdir|
      project_root = Pathname(tmpdir)
      FileUtils.mkdir_p(project_root.join("db", "migrate"))
      File.write(project_root.join("db", "migrate", "20260330190000_create_runtime_executions.rb"), "# migration\n")

      with_redefined_singleton_method(
        Open3,
        :capture3,
        ->(*args) { capture3_calls << args; ["", "", success_status] }
      ) do
        ManualAcceptanceSupport.sync_fenix_runtime_source_to_docker_container!(
          container_name: "fenix-capstone",
          project_root: project_root
        )
      end
    end

    assert_equal 3, capture3_calls.length
    assert_equal(
      ["docker", "exec", "fenix-capstone", "rm", "-rf", "/rails/db"],
      capture3_calls.first
    )
    assert_equal(
      ["docker", "exec", "fenix-capstone", "mkdir", "-p", "/rails"],
      capture3_calls.second
    )
    assert_equal "docker", capture3_calls.third.fetch(0)
    assert_equal "cp", capture3_calls.third.fetch(1)
    assert_equal "fenix-capstone:/rails/db", capture3_calls.third.fetch(3)
  end

  test "restart_docker_fenix_runtime_worker! starts detached worker commands without a shell wrapper" do
    capture3_calls = []
    success_status = stub_process_status(success: true)
    ps_output = "27806 sh -lc cd /rails && nohup bin/jobs start >>/tmp/runtime-jobs.log 2>&1 </dev/null &\n26984 ruby bin/rails runtime:control_loop_forever\n"

    with_redefined_singleton_method(
      ManualAcceptanceSupport,
      :sync_fenix_runtime_source_to_docker_container!,
      ->(container_name:) { container_name }
    ) do
      with_redefined_singleton_method(
        Open3,
        :capture3,
        lambda do |*args|
          capture3_calls << args

          if args == ["docker", "exec", "fenix-capstone", "sh", "-lc", "ps -eo args="]
            [ps_output, "", success_status]
          else
            ["", "", success_status]
          end
        end
      ) do
        ManualAcceptanceSupport.restart_docker_fenix_runtime_worker!(
          machine_credential: "token",
          execution_machine_credential: "token",
          container_name: "fenix-capstone",
          core_matrix_base_url: "http://host.docker.internal:3000"
        )
      end
    end

    assert_includes(
      capture3_calls,
      [
        "docker",
        "exec",
        "-d",
        "-e",
        "CORE_MATRIX_BASE_URL=http://host.docker.internal:3000",
        "-e",
        "CORE_MATRIX_MACHINE_CREDENTIAL=token",
        "-e",
        "CORE_MATRIX_EXECUTION_MACHINE_CREDENTIAL=token",
        "-e",
        "RAILS_ENV=production",
        "-e",
        "FENIX_WORKSPACE_ROOT=/workspace",
        "-w",
        "/rails",
        "fenix-capstone",
        "bin/jobs",
        "start",
      ]
    )
    assert_includes(
      capture3_calls,
      [
        "docker",
        "exec",
        "-d",
        "-e",
        "CORE_MATRIX_BASE_URL=http://host.docker.internal:3000",
        "-e",
        "CORE_MATRIX_MACHINE_CREDENTIAL=token",
        "-e",
        "CORE_MATRIX_EXECUTION_MACHINE_CREDENTIAL=token",
        "-e",
        "RAILS_ENV=production",
        "-e",
        "FENIX_WORKSPACE_ROOT=/workspace",
        "-w",
        "/rails",
        "fenix-capstone",
        "bin/rails",
        "runtime:control_loop_forever",
      ]
    )
  end

  private

  def with_redefined_singleton_method(target, method_name, replacement)
    singleton = target.singleton_class
    original = target.method(method_name)
    singleton.send(:define_method, method_name, &replacement)
    yield
  ensure
    singleton.send(:define_method, method_name, original)
  end

  def stub_process_status(success:)
    Struct.new(:success?, :exitstatus).new(success, success ? 0 : 1)
  end
end
