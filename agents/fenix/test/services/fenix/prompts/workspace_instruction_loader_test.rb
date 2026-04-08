require "test_helper"
require "tmpdir"

class Fenix::Prompts::WorkspaceInstructionLoaderTest < ActiveSupport::TestCase
  test "loads AGENTS instructions from the workspace root" do
    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      root = Pathname.new(workspace_root)
      root.join("AGENTS.md").write("Keep changes scoped to the requested subproject.\n")

      loaded = Fenix::Prompts::WorkspaceInstructionLoader.call(workspace_root: workspace_root)

      assert_equal "Keep changes scoped to the requested subproject.\n", loaded
    end
  end

  test "returns nil when the workspace does not declare AGENTS instructions" do
    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      assert_nil Fenix::Prompts::WorkspaceInstructionLoader.call(workspace_root: workspace_root)
    end
  end
end
