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
bin/rails runner 'AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all; result = Installations::BootstrapFirstAdmin.call(name: "Primary Installation", email: "admin@example.com", password: "Password123!", password_confirmation: "Password123!", display_name: "Primary Admin"); puts({installation_count: Installation.count, identity_count: Identity.count, user_roles: User.order(:id).pluck(:role), audit_actions: AuditLog.order(:action).pluck(:action)}.to_json)'
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
bin/rails runner 'AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all'
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
bin/rails runner 'AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all; bootstrap = Installations::BootstrapFirstAdmin.call(name: "Primary Installation", email: "admin@example.com", password: "Password123!", password_confirmation: "Password123!", display_name: "Primary Admin"); invitation = Invitation.issue!(installation: bootstrap.installation, inviter: bootstrap.user, email: "member@example.com", expires_at: 2.days.from_now); result = Invitations::Consume.call(token: invitation.plaintext_token, password: "Password123!", password_confirmation: "Password123!", display_name: "Member User"); puts({user_count: User.count, consumed_at: result.invitation.reload.consumed_at.present?, invited_email: result.identity.email, audit_actions: AuditLog.order(:action).pluck(:action)}.to_json)'
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
bin/rails runner 'AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all'
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
bin/rails runner 'AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all; bootstrap = Installations::BootstrapFirstAdmin.call(name: "Primary Installation", email: "admin@example.com", password: "Password123!", password_confirmation: "Password123!", display_name: "Primary Admin"); invitation = Invitation.issue!(installation: bootstrap.installation, inviter: bootstrap.user, email: "member@example.com", expires_at: 2.days.from_now); consume = Invitations::Consume.call(token: invitation.plaintext_token, password: "Password123!", password_confirmation: "Password123!", display_name: "Member User"); Users::GrantAdmin.call(user: consume.user, actor: bootstrap.user); Users::RevokeAdmin.call(user: consume.user, actor: bootstrap.user); begin Users::RevokeAdmin.call(user: bootstrap.user, actor: bootstrap.user); rescue => error; guard = error.class.name; end; puts({member_role: consume.user.reload.role, bootstrap_role: bootstrap.user.reload.role, guard_error: guard, audit_actions: AuditLog.order(:created_at).pluck(:action)}.to_json)'
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
bin/rails runner 'AuditLog.delete_all; Session.delete_all; Invitation.delete_all; User.delete_all; Identity.delete_all; Installation.delete_all'
```
