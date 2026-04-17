#!/usr/bin/env ruby
# VERIFICATION_MODE: operator_cli_surface
# This scenario validates the operator setup path through bundle exec ./exe/cmctl
# and only uses verification-owned backend hooks where the CLI has no discovery
# surface yet.

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "verification/hosted/core_matrix"

agent_base_url = ENV.fetch("FENIX_RUNTIME_BASE_URL", "http://127.0.0.1:3101")
artifact_stamp = ENV.fetch("CORE_MATRIX_CLI_OPERATOR_SMOKE_ARTIFACT_STAMP") do
  "#{Time.current.strftime("%Y-%m-%d-%H%M%S")}-core-matrix-cli-operator-smoke"
end
artifact_dir = Verification.repo_root.join("verification", "artifacts", artifact_stamp)

Verification::ManualSupport.reset_backend_state!
FileUtils.rm_rf(artifact_dir)
FileUtils.mkdir_p(artifact_dir)

init_bootstrap = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "init-bootstrap",
  args: ["init"],
  input: [
    Verification::ManualSupport::CONTROL_BASE_URL,
    "Primary Installation",
    "admin@example.com",
    "Password123!",
    "Password123!",
    "Primary Admin",
  ].join("\n") + "\n"
)

installation = Installation.order(:id).last || raise("expected CLI bootstrap to create an installation")

auth_logout = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "auth-logout",
  args: ["auth", "logout"]
)
auth_login = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "auth-login",
  args: ["auth", "login"],
  input: [
    "admin@example.com",
    "Password123!",
  ].join("\n") + "\n"
)

registration = Verification::ManualSupport.register_bundled_runtime_from_manifest!(
  installation: installation,
  runtime_base_url: agent_base_url,
  execution_runtime_fingerprint: "verification-cli-operator-smoke-environment",
  fingerprint: "verification-cli-operator-smoke-runtime"
)

init_refresh = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "init-refresh",
  args: ["init"]
)

codex_login_thread = Thread.new do
  Verification::CliSupport.run!(
    artifact_dir: artifact_dir,
    label: "providers-codex-login",
    args: ["providers", "codex", "login"]
  )
end
Verification::ManualSupport.wait_for_pending_codex_authorization_session!(
  installation: installation,
  timeout_seconds: 45
)
Verification::ManualSupport.complete_pending_codex_authorization!(installation: installation)
codex_login = codex_login_thread.value

workspace_create = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "workspace-create",
  args: ["workspace", "create", "--name", "CLI Smoke Workspace"]
)
selected_workspace_id = workspace_create.fetch("config").fetch("workspace_id")

workspace_use = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "workspace-use",
  args: ["workspace", "use", selected_workspace_id]
)

agent_attach = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "agent-attach",
  args: ["agent", "attach", "--workspace-id", selected_workspace_id, "--agent-id", registration.agent.public_id]
)

status = Verification::CliSupport.run!(
  artifact_dir: artifact_dir,
  label: "status",
  args: ["status"]
)

cli_config = status.fetch("config")
cli_credentials = status.fetch("credentials")
attached_workspace_agent = WorkspaceAgent.find_by_public_id!(cli_config.fetch("workspace_agent_id"))

Verification::ManualSupport.write_json(
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
    "auth_logout_stdout_path" => auth_logout.fetch("stdout_path"),
    "auth_login_stdout_path" => auth_login.fetch("stdout_path"),
    "init_refresh_stdout_path" => init_refresh.fetch("stdout_path"),
    "providers_codex_login_stdout_path" => codex_login.fetch("stdout_path"),
    "workspace_use_stdout_path" => workspace_use.fetch("stdout_path"),
    "agent_attach_stdout_path" => agent_attach.fetch("stdout_path"),
  }
)
