#!/usr/bin/env ruby
# ACCEPTANCE_MODE: operator_cli_surface
# This scenario validates the operator setup path through cmctl and only uses
# acceptance-owned backend hooks where the CLI has no discovery surface yet.

require_relative "../lib/boot"

agent_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
artifact_stamp = ENV.fetch("CORE_MATRIX_CLI_OPERATOR_SMOKE_ARTIFACT_STAMP") do
  "#{Time.current.strftime("%Y-%m-%d-%H%M%S")}-core-matrix-cli-operator-smoke"
end
artifact_dir = AcceptanceHarness.repo_root.join("acceptance", "artifacts", artifact_stamp)

Acceptance::ManualSupport.reset_backend_state!
FileUtils.rm_rf(artifact_dir)
FileUtils.mkdir_p(artifact_dir)

init_bootstrap = Acceptance::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "init-bootstrap",
  args: ["init"],
  input: [
    Acceptance::ManualSupport::CONTROL_BASE_URL,
    "Primary Installation",
    "admin@example.com",
    "Password123!",
    "Password123!",
    "Primary Admin",
  ].join("\n") + "\n"
)

installation = Installation.order(:id).last || raise("expected CLI bootstrap to create an installation")
registration = Acceptance::ManualSupport.register_bundled_runtime_from_manifest!(
  installation: installation,
  runtime_base_url: agent_base_url,
  execution_runtime_fingerprint: "acceptance-cli-operator-smoke-environment",
  fingerprint: "acceptance-cli-operator-smoke-runtime"
)

init_refresh = Acceptance::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "init-refresh",
  args: ["init"]
)

workspace_create = Acceptance::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "workspace-create",
  args: ["workspace", "create", "--name", "CLI Smoke Workspace"]
)
selected_workspace_id = workspace_create.fetch("config").fetch("workspace_id")

workspace_use = Acceptance::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "workspace-use",
  args: ["workspace", "use", selected_workspace_id]
)

agent_attach = Acceptance::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "agent-attach",
  args: ["agent", "attach", "--workspace-id", selected_workspace_id, "--agent-id", registration.agent.public_id]
)

status = Acceptance::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "status",
  args: ["status"]
)

cli_config = status.fetch("config")
cli_credentials = status.fetch("credentials")
attached_workspace_agent = WorkspaceAgent.find_by_public_id!(cli_config.fetch("workspace_agent_id"))

Acceptance::ManualSupport.write_json(
  {
    "scenario" => "core_matrix_cli_operator_smoke_validation",
    "passed" => cli_config.fetch("workspace_id") == selected_workspace_id &&
      attached_workspace_agent.active? &&
      cli_credentials.fetch("session_token").present?,
    "artifact_dir" => artifact_dir.to_s,
    "installation_name" => installation.name,
    "installation_bootstrap_state" => installation.bootstrap_state,
    "agent_id" => registration.agent.public_id,
    "workspace_id" => selected_workspace_id,
    "workspace_agent_id" => cli_config.fetch("workspace_agent_id"),
    "status_stdout_path" => status.fetch("stdout_path"),
    "init_bootstrap_stdout_path" => init_bootstrap.fetch("stdout_path"),
    "init_refresh_stdout_path" => init_refresh.fetch("stdout_path"),
    "workspace_use_stdout_path" => workspace_use.fetch("stdout_path"),
    "agent_attach_stdout_path" => agent_attach.fetch("stdout_path"),
  }
)
