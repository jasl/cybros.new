# Deployment Credential Lifecycle Controls

## Purpose

Task 11.3 adds explicit lifecycle controls for the active agent-session
credential behind an `AgentProgramVersion`: rotation, revocation, and
retirement. These controls keep program-version identity, credential
invalidation, auditability, and scheduling eligibility under kernel authority.

## Rotation

- `AgentProgramVersions::RotateMachineCredential` issues a fresh
  agent-session credential for the selected `AgentProgramVersion`
- rotation updates the stored credential digest atomically inside one
  transaction
- the previous plaintext credential becomes unusable immediately after
  rotation commits
- rotation records the audit action
  `agent_program_version.machine_credential_rotated`

## Revocation

- `AgentProgramVersions::RevokeMachineCredential` invalidates the current machine
  credential by replacing the stored digest with a fresh unreachable digest
- revocation moves the active agent session to `health_status = "offline"`
- revocation sets `auto_resume_eligible = false`
- revocation records `unavailability_reason = "machine_credential_revoked"`
- revocation records the audit action
  `agent_program_version.machine_credential_revoked`

## Retirement

- `AgentProgramVersions::Retire` closes the active agent session for the
  selected `AgentProgramVersion` and marks its health as `retired`
- retirement sets `auto_resume_eligible = false`
- retirement records `unavailability_reason = "deployment_retired"`
- retirement records the audit action `agent_program_version.retired`

## Scheduling Eligibility

- `AgentProgramVersion#eligible_for_scheduling?` is the scheduling gate for future
  execution
- a program version is eligible only when:
  - it has an active agent session
  - that active agent session is `healthy`
- `Workflows::ResolveModelSelector` rejects future scheduling when the selected
  program version is no longer eligible

## Audit Scope

- all three lifecycle services write audit rows against the affected agent
  session or `AgentProgramVersion`
- audit metadata includes the agent program reference and any related default
  execution runtime reference when present
- actor attribution is supported for rotation, revocation, and retirement

## Failure Modes

- rotated credentials stop authenticating immediately after the new digest is
  committed
- revoked credentials stop authenticating before any later re-registration
- retired program versions can still exist as historical rows, but they are not
  eligible for future scheduling

## Retained Implementation Notes

- retirement does not invent a second program-version retirement state machine; it
  composes the existing `health_status` and `bootstrap_state` models
- scheduling ineligibility is enforced at model-selector resolution time so the
  existing workflow scheduling path inherits the lifecycle gate without adding a
  parallel scheduler abstraction
