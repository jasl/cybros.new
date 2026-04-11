require "test_helper"
require "tmpdir"

class Nexus::Shared::Environment::WorkspaceEnvOverlayTest < ActiveSupport::TestCase
  test "returns an empty overlay when the workspace env file is absent" do
    Dir.mktmpdir("nexus-workspace-") do |workspace_root|
      assert_equal({}, Nexus::Shared::Environment::WorkspaceEnvOverlay.call(workspace_root: workspace_root))
    end
  end

  test "rejects reserved keys" do
    Dir.mktmpdir("nexus-workspace-") do |workspace_root|
      overlay_path = Pathname.new(workspace_root).join(".nexus", "workspace.env")
      FileUtils.mkdir_p(overlay_path.dirname)
      overlay_path.write("PATH=/tmp/fake\n")

      error = assert_raises(Nexus::Shared::Environment::WorkspaceEnvOverlay::ValidationError) do
        Nexus::Shared::Environment::WorkspaceEnvOverlay.call(workspace_root: workspace_root)
      end

      assert_match(/reserved workspace env key/i, error.message)
      assert_match(/PATH/, error.message)
    end
  end

  test "parses comments blank lines and export prefixes" do
    Dir.mktmpdir("nexus-workspace-") do |workspace_root|
      overlay_path = Pathname.new(workspace_root).join(".nexus", "workspace.env")
      FileUtils.mkdir_p(overlay_path.dirname)
      overlay_path.write(<<~ENV)
        # comment

        HELLO=workspace
        export FEATURE_FLAG=enabled
      ENV

      assert_equal(
        {
          "HELLO" => "workspace",
          "FEATURE_FLAG" => "enabled",
        },
        Nexus::Shared::Environment::WorkspaceEnvOverlay.call(workspace_root: workspace_root)
      )
    end
  end

  test "rejects invalid lines" do
    Dir.mktmpdir("nexus-workspace-") do |workspace_root|
      overlay_path = Pathname.new(workspace_root).join(".nexus", "workspace.env")
      FileUtils.mkdir_p(overlay_path.dirname)
      overlay_path.write("NOT_A_VALID_ENV_LINE\n")

      error = assert_raises(Nexus::Shared::Environment::WorkspaceEnvOverlay::ValidationError) do
        Nexus::Shared::Environment::WorkspaceEnvOverlay.call(workspace_root: workspace_root)
      end

      assert_match(/invalid workspace env line/i, error.message)
    end
  end
end
