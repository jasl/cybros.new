require "test_helper"
require "tmpdir"
require Rails.root.join("../acceptance/lib/capability_activation")

class AcceptanceCapabilityActivationTest < ActiveSupport::TestCase
  test "workspace editing probe counts only meaningful app files" do
    Dir.mktmpdir("capability-activation") do |tmpdir|
      app_dir = Pathname(tmpdir).join("game-2048")
      FileUtils.mkdir_p(app_dir.join("src"))
      FileUtils.mkdir_p(app_dir.join("node_modules/pkg"))
      FileUtils.mkdir_p(app_dir.join("dist/assets"))
      File.write(app_dir.join("package.json"), "{}\n")
      File.write(app_dir.join("src/main.tsx"), "export const App = () => null;\n")
      File.write(app_dir.join("node_modules/pkg/index.js"), "module.exports = {};\n")
      File.write(app_dir.join("dist/assets/app.js"), "console.log('built');\n")

      workspace_validation = app_dir.join("workspace-validation.md")
      File.write(workspace_validation, "# Workspace Validation\n")

      report = Acceptance::CapabilityActivation.build(
        contract: {
          "scenario" => "workspace_editing_probe",
          "capabilities" => [
            { "key" => "workspace_editing", "required" => true },
          ],
        },
        artifact_paths: { "workspace_validation" => workspace_validation },
        workspace_paths: { "generated_app_dir" => app_dir }
      )

      row = report.fetch("required_capabilities").first

      assert_equal true, row.fetch("activated")
      assert_includes row.fetch("artifact_evidence"), app_dir.to_s
      assert_includes row.fetch("artifact_evidence"), workspace_validation.to_s
      assert_includes row.fetch("notes"), "meaningful_file_count=2"
      assert_includes row.fetch("notes"), "meaningful_file_samples=package.json,src/main.tsx"
    end
  end
end
