require "test_helper"

class Fenix::Runtime::SystemToolRegistryTest < ActiveSupport::TestCase
  test "supported tool names are the reviewable tool names" do
    assert_equal(
      Fenix::Runtime::SystemToolRegistry.supported_tool_names.sort,
      Fenix::Hooks::ReviewToolCall.supported_tool_names.sort
    )
  end

  test "registry-backed tool names are the execution-topology tool names" do
    assert_equal(
      Fenix::Runtime::SystemToolRegistry.registry_backed_tool_names.sort,
      Fenix::Runtime::ExecutionTopology.registry_backed_tool_names.sort
    )
  end

  test "registry entries expose executor and projector metadata" do
    exec_command_entry = Fenix::Runtime::SystemToolRegistry.fetch!("exec_command")

    assert_equal Fenix::Runtime::ToolExecutors::ExecCommand, exec_command_entry.fetch(:executor)
    assert_equal Fenix::Hooks::ToolResultProjectors::ExecCommand, exec_command_entry.fetch(:projector)
    assert_equal true, exec_command_entry.fetch(:registry_backed)

    calculator_entry = Fenix::Runtime::SystemToolRegistry.fetch!("calculator")

    assert_equal Fenix::Runtime::ToolExecutors::Calculator, calculator_entry.fetch(:executor)
    assert_equal Fenix::Hooks::ToolResultProjectors::Calculator, calculator_entry.fetch(:projector)
    assert_equal false, calculator_entry.fetch(:registry_backed)
  end
end
