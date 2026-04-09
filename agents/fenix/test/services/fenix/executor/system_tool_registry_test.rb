require "test_helper"

class Fenix::Executor::SystemToolRegistryTest < ActiveSupport::TestCase
  test "supported tool names cover the command-run and browser executor slices" do
    assert_equal(
      %w[
        browser_close
        browser_get_content
        browser_list
        browser_navigate
        browser_open
        browser_screenshot
        browser_session_info
        command_run_list
        command_run_read_output
        command_run_terminate
        command_run_wait
        exec_command
        process_exec
        process_list
        process_proxy_info
        process_read_output
        write_stdin
      ],
      Fenix::Executor::SystemToolRegistry.supported_tool_names.sort
    )
  end

  test "registry entries expose executor and catalog metadata" do
    exec_command_entry = Fenix::Executor::SystemToolRegistry.fetch!("exec_command")

    assert_equal Fenix::Executor::ToolExecutors::ExecCommand, exec_command_entry.fetch(:executor)
    assert_equal true, exec_command_entry.fetch(:registry_backed)
    assert_equal "command_run", exec_command_entry.dig(:catalog_entry, "operator_group")
    assert_equal true, exec_command_entry.dig(:catalog_entry, "supports_streaming_output")
    assert_equal "fenix/executor/command_run", exec_command_entry.dig(:catalog_entry, "implementation_ref")
  end

  test "browser registry entries expose the browser executor slice" do
    browser_open_entry = Fenix::Executor::SystemToolRegistry.fetch!("browser_open")

    assert_equal Fenix::Executor::ToolExecutors::Browser, browser_open_entry.fetch(:executor)
    assert_equal true, browser_open_entry.fetch(:registry_backed)
    assert_equal "browser_session", browser_open_entry.dig(:catalog_entry, "operator_group")
    assert_equal "browser_session", browser_open_entry.dig(:catalog_entry, "resource_identity_kind")
    assert_equal false, browser_open_entry.dig(:catalog_entry, "supports_streaming_output")
  end

  test "process registry entries expose the detached process executor slice" do
    process_exec_entry = Fenix::Executor::SystemToolRegistry.fetch!("process_exec")
    process_proxy_info_entry = Fenix::Executor::SystemToolRegistry.fetch!("process_proxy_info")

    assert_equal true, process_exec_entry.fetch(:registry_backed)
    assert_equal "process_run", process_exec_entry.dig(:catalog_entry, "operator_group")
    assert_equal "process_run", process_exec_entry.dig(:catalog_entry, "resource_identity_kind")
    assert_equal true, process_exec_entry.dig(:catalog_entry, "mutates_state")
    assert_equal "executor_program", process_exec_entry.dig(:catalog_entry, "tool_kind")
    assert_equal false, process_proxy_info_entry.dig(:catalog_entry, "mutates_state")
    assert_equal ["process_run_id"], process_proxy_info_entry.dig(:catalog_entry, "input_schema", "required")
  end
end
