require "test_helper"
require "tmpdir"

class Prompts::WorkspaceInstructionLoaderTest < ActiveSupport::TestCase
  test "loads workspace instructions from AGENTS.md" do
    Dir.mktmpdir("nexus-workspace-") do |workspace_root|
      Pathname.new(workspace_root).join("AGENTS.md").write("Stay in this workspace.\n")

      loaded = Prompts::WorkspaceInstructionLoader.call(workspace_root: workspace_root)

      assert_equal "Stay in this workspace.\n", loaded
    end
  end
end
