# Core Matrix Kernel Manual Validation Checklist

## Status

Living checklist for real-environment verification during the backend greenfield build.

The implementation phase must keep this document updated. Each complex flow should end with exact commands, setup notes, and expected outcomes that can be reproduced later.

Current-batch rule:

- keep this checklist backend-reproducible through shell commands, HTTP requests, Rails console actions, and dummy runtime scripts
- do not add browser-only or human-facing UI validation steps in the current backend greenfield batch

## Prerequisites

- `cd core_matrix`
- application boots under `bin/dev`
- test or development data needed for the target flow is documented inline
- any helper scripts or dummy agent processes used for validation are referenced inline

## Flows To Maintain

- first-admin bootstrap
- invitation creation and consumption
- admin grant and revoke
- bundled Fenix auto-registration and first-admin auto-binding when configured
- agent enrollment, registration, handshake, heartbeat, outage recovery, and deployment retirement
- drift-triggered manual resume and manual retry
- user-agent binding and default workspace creation
- provider catalog load, governance changes, and related audit rows
- conversation root creation, automation root creation, branch creation, thread creation, checkpoint creation, archive and unarchive
- conversation interactive selector `auto | explicit candidate`, tail edit, rollback or fork editing, retry, rerun, swipe selection, queued turn handling, and runtime pinning
- automation turn creation without a transcript-bearing user message, persisted turn-origin metadata, and read-only automation history inspection
- attachments, imports, summary segments, visibility overlays, multimodal model access, and unsupported-capability fallback behavior
- workflow scheduling, dynamic DAG expansion, fan-out or fan-in joins, structured wait-state transitions, role-local model fallback after entitlement exhaustion, explicit-candidate no-fallback failure, approvals, human form requests, human task requests, same-workflow human-interaction resumption, short-lived turn commands, long-lived background services, process output replay, subagent runs, lightweight swarm coordination metadata, canonical variable writes and promotions, and lease recovery
- replaceable live projection streams for streaming text, progress, and status surfaces while preserving append-only event history
- agent transcript cursor pagination and canonical variable API reads through machine-facing endpoints
- machine credential rotation and revocation
- one-time selector override during manual recovery
- publication internal-public access, external-public access, read-only projection, access logging, and revoke

## Checklist Template

For each flow, keep:

- goal
- prerequisites
- exact commands
- exact endpoints, shell requests, or Rails console actions
- expected rows or state changes
- expected logs or visible outcomes
- cleanup steps

## First-Admin Bootstrap

- goal:
  verify the backend bootstrap creates exactly one installation, one identity,
  one admin user, and one bootstrap audit row
- prerequisites:
  - `cd core_matrix`
  - `bin/rails db:migrate`
  - development database can be reset for this flow
- exact commands:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all; result = Installations::BootstrapFirstAdmin.call(name: "Primary Installation", email: "admin@example.com", password: "Password123!", password_confirmation: "Password123!", display_name: "Primary Admin"); puts({installation_count: Installation.count, identity_count: Identity.count, user_roles: User.order(:id).pluck(:role), audit_actions: AuditLog.order(:action).pluck(:action)}.to_json)'
```

- expected rows or state changes:
  - one `installations` row with `bootstrap_state = "bootstrapped"`
  - one `identities` row for `admin@example.com`
  - one `users` row with `role = "admin"`
  - one `audit_logs` row with `action = "installation.bootstrapped"`
- expected logs or visible outcomes:
  - JSON output reports `installation_count: 1`
  - JSON output includes `user_roles: ["admin"]`
  - JSON output includes `audit_actions: ["installation.bootstrapped"]`
- cleanup steps:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all'
```

## Invitation Creation And Consumption

- goal:
  verify an invitation token can be issued once, consumed once, and produces a
  new identity plus user with an audit row
- prerequisites:
  - run the first-admin bootstrap flow or start from an empty development
    database
- exact commands:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all; bootstrap = Installations::BootstrapFirstAdmin.call(name: "Primary Installation", email: "admin@example.com", password: "Password123!", password_confirmation: "Password123!", display_name: "Primary Admin"); invitation = Invitation.issue!(installation: bootstrap.installation, inviter: bootstrap.user, email: "member@example.com", expires_at: 2.days.from_now); result = Invitations::Consume.call(token: invitation.plaintext_token, password: "Password123!", password_confirmation: "Password123!", display_name: "Member User"); puts({user_count: User.count, consumed_at: result.invitation.reload.consumed_at.present?, invited_email: result.identity.email, audit_actions: AuditLog.order(:action).pluck(:action)}.to_json)'
```

- expected rows or state changes:
  - invitation row has `consumed_at` set
  - second identity exists for `member@example.com`
  - second user exists with `role = "member"`
  - `audit_logs` includes `invitation.consumed`
- expected logs or visible outcomes:
  - JSON output reports `user_count: 2`
  - JSON output reports `consumed_at: true`
  - JSON output reports `invited_email: "member@example.com"`
- cleanup steps:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all'
```

## Admin Grant And Revoke

- goal:
  verify admin promotion and demotion write audit rows and preserve the
  last-active-admin safety rule
- prerequisites:
  - run the invitation consumption flow or start from an empty development
    database
- exact commands:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all; bootstrap = Installations::BootstrapFirstAdmin.call(name: "Primary Installation", email: "admin@example.com", password: "Password123!", password_confirmation: "Password123!", display_name: "Primary Admin"); invitation = Invitation.issue!(installation: bootstrap.installation, inviter: bootstrap.user, email: "member@example.com", expires_at: 2.days.from_now); consume = Invitations::Consume.call(token: invitation.plaintext_token, password: "Password123!", password_confirmation: "Password123!", display_name: "Member User"); Users::GrantAdmin.call(user: consume.user, actor: bootstrap.user); Users::RevokeAdmin.call(user: consume.user, actor: bootstrap.user); begin Users::RevokeAdmin.call(user: bootstrap.user, actor: bootstrap.user); rescue => error; guard = error.class.name; end; puts({member_role: consume.user.reload.role, bootstrap_role: bootstrap.user.reload.role, guard_error: guard, audit_actions: AuditLog.order(:created_at).pluck(:action)}.to_json)'
```

- expected rows or state changes:
  - invited user role changes to `admin` and then back to `member`
  - bootstrap user remains `admin`
  - last-admin revoke is blocked
  - `audit_logs` includes `user.admin_granted` and `user.admin_revoked`
- expected logs or visible outcomes:
  - JSON output reports `member_role: "member"`
  - JSON output reports `bootstrap_role: "admin"`
  - JSON output reports `guard_error: "Users::RevokeAdmin::LastAdminError"`
- cleanup steps:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all'
```

## Agent Enrollment, Registration, And Heartbeat

- goal:
  verify enrollment issuance mints a one-time token, registration creates a
  pending deployment plus capability snapshot, and the first healthy heartbeat
  activates the deployment
- prerequisites:
  - `cd core_matrix`
  - `bin/rails db:migrate`
  - development database can be reset for this flow
- exact commands:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all; bootstrap = Installations::BootstrapFirstAdmin.call(name: "Primary Installation", email: "admin@example.com", password: "Password123!", password_confirmation: "Password123!", display_name: "Primary Admin"); agent_installation = AgentInstallation.create!(installation: bootstrap.installation, visibility: "global", key: "fenix", display_name: "Bundled Fenix", lifecycle_state: "active"); environment = ExecutionEnvironment.create!(installation: bootstrap.installation, kind: "local", connection_metadata: {"transport" => "http", "base_url" => "http://127.0.0.1:4100"}, lifecycle_state: "active"); enrollment = AgentEnrollments::Issue.call(agent_installation: agent_installation, actor: bootstrap.user, expires_at: 2.hours.from_now); registration = AgentDeployments::Register.call(enrollment_token: enrollment.plaintext_token, execution_environment: environment, fingerprint: "fenix-machine-001", endpoint_metadata: {"transport" => "http", "base_url" => "http://127.0.0.1:4100"}, protocol_version: "2026-03-24", sdk_version: "fenix-0.1.0", protocol_methods: [{"method_id" => "agent_health"}, {"method_id" => "capabilities_handshake"}], tool_catalog: [{"tool_name" => "shell_exec", "tool_kind" => "builtin"}], config_schema_snapshot: {"type" => "object", "properties" => {}}, conversation_override_schema_snapshot: {"type" => "object", "properties" => {}}, default_config_snapshot: {"sandbox" => "workspace-write"}); AgentDeployments::RecordHeartbeat.call(deployment: registration.deployment, health_status: "healthy", health_metadata: {"latency_ms" => 45}, auto_resume_eligible: true); puts({enrollment_consumed: registration.enrollment.reload.consumed_at.present?, deployment_state: registration.deployment.reload.bootstrap_state, health_status: registration.deployment.health_status, capability_versions: registration.deployment.capability_snapshots.order(:version).pluck(:version), audit_actions: AuditLog.order(:created_at).pluck(:action)}.to_json)'
```

- expected rows or state changes:
  - one `agent_enrollments` row exists and has `consumed_at` set
  - one `agent_deployments` row exists with `bootstrap_state = "active"`
  - one `capability_snapshots` row exists with `version = 1`
  - `audit_logs` includes `agent_enrollment.issued` and
    `agent_deployment.registered`
- expected logs or visible outcomes:
  - JSON output reports `enrollment_consumed: true`
  - JSON output reports `deployment_state: "active"`
  - JSON output reports `health_status: "healthy"`
  - JSON output reports `capability_versions: [1]`
- cleanup steps:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all'
```

## User Binding And Default Workspace

- goal:
  verify enabling a shared agent creates one binding per user-agent pair and
  one private default workspace per binding
- prerequisites:
  - `cd core_matrix`
  - `bin/rails db:migrate`
  - development database can be reset for this flow
- exact commands:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all; bootstrap = Installations::BootstrapFirstAdmin.call(name: "Primary Installation", email: "admin@example.com", password: "Password123!", password_confirmation: "Password123!", display_name: "Primary Admin"); member_identity = Identity.create!(email: "member@example.com", password: "Password123!", password_confirmation: "Password123!", auth_metadata: {}); member = User.create!(installation: bootstrap.installation, identity: member_identity, role: "member", display_name: "Member User", preferences: {}); agent_installation = AgentInstallation.create!(installation: bootstrap.installation, visibility: "global", key: "shared-agent", display_name: "Shared Agent", lifecycle_state: "active"); first = UserAgentBindings::Enable.call(user: bootstrap.user, agent_installation: agent_installation); duplicate = UserAgentBindings::Enable.call(user: bootstrap.user, agent_installation: agent_installation); second = UserAgentBindings::Enable.call(user: member, agent_installation: agent_installation); puts({binding_count: UserAgentBinding.count, default_workspace_count: Workspace.where(is_default: true).count, duplicate_binding_reused: first.binding.id == duplicate.binding.id, workspace_users: Workspace.order(:id).pluck(:user_id), privacy_values: Workspace.order(:id).pluck(:privacy)}.to_json)'
```

- expected rows or state changes:
  - one binding row exists for the admin user and shared agent pair
  - repeated enable does not create a duplicate binding
  - a second user gets a distinct binding and distinct default workspace
  - all workspaces stay `privacy = "private"`
- expected logs or visible outcomes:
  - JSON output reports `binding_count: 2`
  - JSON output reports `default_workspace_count: 2`
  - JSON output reports `duplicate_binding_reused: true`
  - JSON output reports `privacy_values: ["private", "private"]`
- cleanup steps:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all'
```

## Bundled Fenix Auto-Registration And First-Admin Auto-Binding

- goal:
  verify bundled bootstrap is opt-in, reconciles bundled runtime rows before
  binding, and reuses the same logical and deployment rows on repeated
  reconciliation
- prerequisites:
  - `cd core_matrix`
  - `bin/rails db:migrate`
  - development database can be reset for this flow
- exact commands:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all; bundled_configuration = {enabled: true, agent_key: "fenix", display_name: "Bundled Fenix", visibility: "global", lifecycle_state: "active", environment_kind: "local", connection_metadata: {"transport" => "http", "base_url" => "http://127.0.0.1:4100"}, fingerprint: "bundled-fenix-runtime", protocol_version: "2026-03-24", sdk_version: "fenix-0.1.0", protocol_methods: [{"method_id" => "agent_health"}, {"method_id" => "capabilities_handshake"}], tool_catalog: [{"tool_name" => "shell_exec", "tool_kind" => "builtin"}], config_schema_snapshot: {"type" => "object", "properties" => {}}, conversation_override_schema_snapshot: {"type" => "object", "properties" => {}}, default_config_snapshot: {"sandbox" => "workspace-write"}}; bootstrap = Installations::BootstrapFirstAdmin.call(name: "Primary Installation", email: "admin@example.com", password: "Password123!", password_confirmation: "Password123!", display_name: "Primary Admin", bundled_agent_configuration: bundled_configuration); first_registry = Installations::RegisterBundledAgentRuntime.call(installation: bootstrap.installation, configuration: bundled_configuration); second_registry = Installations::RegisterBundledAgentRuntime.call(installation: bootstrap.installation, configuration: bundled_configuration); binding = UserAgentBinding.find_by!(user: bootstrap.user, agent_installation: first_registry.agent_installation); workspace = Workspace.find_by!(user_agent_binding: binding, is_default: true); puts({agent_installation_ids: [first_registry.agent_installation.id, second_registry.agent_installation.id], deployment_ids: [first_registry.deployment.id, second_registry.deployment.id], agent_count: AgentInstallation.count, deployment_count: AgentDeployment.count, snapshot_count: CapabilitySnapshot.count, binding_count: UserAgentBinding.count, workspace_count: Workspace.count, workspace_private: workspace.private_workspace?}.to_json)'
```

- expected rows or state changes:
  - first-admin bootstrap creates one bundled `agent_installations` row with
    key `fenix`
  - one `execution_environments` row and one active `agent_deployments` row
    exist for the bundled runtime
  - one `user_agent_bindings` row and one default `workspaces` row exist for
    the first admin
  - repeated bundled runtime reconciliation does not duplicate logical or
    deployment rows
- expected logs or visible outcomes:
  - JSON output reports identical `agent_installation_ids`
  - JSON output reports identical `deployment_ids`
  - JSON output reports `agent_count: 1`
  - JSON output reports `deployment_count: 1`
  - JSON output reports `snapshot_count: 1`
  - JSON output reports `workspace_private: true`
- cleanup steps:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all'
```

## Human Interaction Pause And Resume

- goal:
  verify a blocking approval request pauses the existing workflow run, projects
  append-only conversation events, and resumes the same workflow run after
  approval without creating a new turn
- prerequisites:
  - `cd core_matrix`
  - `bin/rails db:migrate`
  - development database can be reset for this flow
- exact commands:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all; bootstrap = Installations::BootstrapFirstAdmin.call(name: "Primary Installation", email: "admin@example.com", password: "Password123!", password_confirmation: "Password123!", display_name: "Primary Admin"); agent_installation = AgentInstallation.create!(installation: bootstrap.installation, visibility: "global", key: "fenix", display_name: "Fenix", lifecycle_state: "active"); environment = ExecutionEnvironment.create!(installation: bootstrap.installation, kind: "local", connection_metadata: {"transport" => "http", "base_url" => "http://127.0.0.1:4100"}, lifecycle_state: "active"); deployment = AgentDeployment.create!(installation: bootstrap.installation, agent_installation: agent_installation, execution_environment: environment, fingerprint: "fenix-machine-001", endpoint_metadata: {"transport" => "http", "base_url" => "http://127.0.0.1:4100"}, protocol_version: "2026-03-24", sdk_version: "fenix-0.1.0", machine_credential_digest: Digest::SHA256.hexdigest("machine-001"), health_status: "healthy", health_metadata: {}, bootstrap_state: "active", last_heartbeat_at: Time.current); capability = CapabilitySnapshot.create!(agent_deployment: deployment, version: 1, protocol_methods: [{"method_id" => "agent_health"}], tool_catalog: [{"tool_name" => "shell_exec"}], config_schema_snapshot: {}, conversation_override_schema_snapshot: {}, default_config_snapshot: {}); deployment.update!(active_capability_snapshot: capability); ProviderEntitlement.create!(installation: bootstrap.installation, provider_handle: "codex_subscription", entitlement_key: "shared_window", window_kind: "rolling_five_hours", window_seconds: 18000, quota_limit: 200000, active: true, metadata: {}); ProviderEntitlement.create!(installation: bootstrap.installation, provider_handle: "openai", entitlement_key: "shared_window", window_kind: "rolling_five_hours", window_seconds: 18000, quota_limit: 200000, active: true, metadata: {}); binding = UserAgentBindings::Enable.call(user: bootstrap.user, agent_installation: agent_installation).binding; workspace = binding.workspaces.find_by!(is_default: true); conversation = Conversations::CreateRoot.call(workspace: workspace); turn = Turns::StartUserTurn.call(conversation: conversation, content: "Need approval", agent_deployment: deployment, resolved_config_snapshot: {}, resolved_model_selection_snapshot: {}); workflow_run = Workflows::CreateForTurn.call(turn: turn, root_node_key: "root", root_node_type: "turn_root", decision_source: "system", metadata: {}); Workflows::Mutate.call(workflow_run: workflow_run, nodes: [{node_key: "human_gate", node_type: "human_interaction", decision_source: "agent_program", metadata: {}}], edges: [{from_node_key: "root", to_node_key: "human_gate"}]); request = HumanInteractions::Request.call(request_type: "ApprovalRequest", workflow_node: workflow_run.reload.workflow_nodes.find_by!(node_key: "human_gate"), blocking: true, request_payload: {"approval_scope" => "publish"}); paused = workflow_run.reload; resolved = HumanInteractions::ResolveApproval.call(approval_request: request, decision: "approved", result_payload: {"comment" => "Ship it"}); puts({wait_before: paused.wait_state, blocking_resource_id: paused.blocking_resource_id, wait_after: resolved.workflow_run.reload.wait_state, same_workflow_run: resolved.workflow_run_id == workflow_run.id, conversation_event_kinds: ConversationEvent.where(conversation: conversation).order(:projection_sequence).pluck(:event_kind), live_projection_kinds: ConversationEvent.live_projection(conversation: conversation).map(&:event_kind), turn_count: conversation.turns.count}.to_json)'
```

- expected rows or state changes:
  - one `human_interaction_requests` row exists with `type = "ApprovalRequest"`
  - the request transitions from `lifecycle_state = "open"` to
    `lifecycle_state = "resolved"`
  - the existing `workflow_runs` row transitions from `wait_state = "waiting"`
    back to `wait_state = "ready"`
  - two append-only `conversation_events` rows exist for the request stream
  - no additional turn is created during request resolution
- expected logs or visible outcomes:
  - JSON output reports `wait_before: "waiting"`
  - JSON output reports `wait_after: "ready"`
  - JSON output reports `same_workflow_run: true`
  - JSON output reports
    `conversation_event_kinds: ["human_interaction.opened", "human_interaction.resolved"]`
  - JSON output reports
    `live_projection_kinds: ["human_interaction.resolved"]`
  - JSON output reports `turn_count: 1`
- cleanup steps:

```bash
bin/rails runner 'AgentDeployment.update_all(active_capability_snapshot_id: nil); CapabilitySnapshot.delete_all; Workspace.delete_all; UserAgentBinding.delete_all; AgentDeployment.delete_all; AgentEnrollment.delete_all; ExecutionEnvironment.delete_all; AgentInstallation.delete_all; AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all'
```
