# Agent Connection Credential Lifecycle Controls

## Purpose

Task 11.3 adds explicit lifecycle controls for the active agent connection
credential behind an `AgentDefinitionVersion`: rotation, revocation, and
retirement. These controls keep agent definition version identity, credential
invalidation, auditability, and scheduling eligibility under kernel authority.

## Rotation

- `AgentConnections::RotateConnectionCredential` issues a fresh
  agent connection credential for the selected `AgentDefinitionVersion`
- rotation updates the stored credential digest atomically inside one
  transaction
- the previous plaintext credential becomes unusable immediately after
  rotation commits
- rotation records the audit action `agent_connection.credential_rotated`

## Revocation

- `AgentConnections::RevokeConnectionCredential` invalidates the current
  agent connection credential by replacing the stored digest with a fresh
  unreachable digest
- revocation moves the active agent connection to `health_status = "offline"`
- revocation sets `auto_resume_eligible = false`
- revocation records `unavailability_reason = "agent_connection_credential_revoked"`
- revocation records the audit action `agent_connection.credential_revoked`

## Retirement

- `AgentDefinitionVersions::Retire` closes the active agent connection for the
  selected `AgentDefinitionVersion` and marks its health as `retired`
- retirement sets `auto_resume_eligible = false`
- retirement records `unavailability_reason = "agent_definition_version_retired"`
- retirement records the audit action `agent_definition_version.retired`

## Scheduling Eligibility

- `AgentDefinitionVersion#eligible_for_scheduling?` is the scheduling gate for future
  execution
- an agent definition version is eligible only when:
  - it has an active agent connection
  - that active agent connection is `healthy`
- `Workflows::ResolveModelSelector` rejects future scheduling when the selected
  agent definition version is no longer eligible

## Audit Scope

- all three lifecycle services write audit rows against the affected agent
  connection or `AgentDefinitionVersion`
- audit metadata includes the agent reference and any related default
  execution runtime reference when present
- actor attribution is supported for rotation, revocation, and retirement

## Failure Modes

- rotated credentials stop authenticating immediately after the new digest is
  committed
- revoked credentials stop authenticating before any later re-registration
- retired agent definition versions can still exist as historical rows, but they are not
  eligible for future scheduling

## Retained Implementation Notes

- retirement does not invent a second agent-definition-version retirement state machine; it
  composes the existing `health_status` and `bootstrap_state` models
- scheduling ineligibility is enforced at model-selector resolution time so the
  existing workflow scheduling path inherits the lifecycle gate without adding a
  parallel scheduler abstraction
