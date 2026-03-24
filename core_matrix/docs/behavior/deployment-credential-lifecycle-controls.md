# Deployment Credential Lifecycle Controls

## Purpose

Task 11.3 adds explicit lifecycle controls for deployment machine credentials:
rotation, revocation, and retirement. These controls keep deployment identity,
credential invalidation, auditability, and scheduling eligibility under kernel
authority.

## Rotation

- `AgentDeployments::RotateMachineCredential` issues a fresh machine secret
  through `AgentDeployment.issue_machine_credential`
- rotation updates the stored credential digest atomically inside one
  transaction
- the previous plaintext credential becomes unusable immediately after
  rotation commits
- rotation records the audit action
  `agent_deployment.machine_credential_rotated`

## Revocation

- `AgentDeployments::RevokeMachineCredential` invalidates the current machine
  credential by replacing the stored digest with a fresh unreachable digest
- revocation moves the deployment to `health_status = "offline"`
- revocation sets `auto_resume_eligible = false`
- revocation records `unavailability_reason = "machine_credential_revoked"`
- revocation records the audit action
  `agent_deployment.machine_credential_revoked`

## Retirement

- `AgentDeployments::Retire` moves the deployment to
  `health_status = "retired"`
- retirement also marks the bootstrap lifecycle as `superseded`
- retirement sets `auto_resume_eligible = false`
- retirement records `unavailability_reason = "deployment_retired"`
- retirement records the audit action `agent_deployment.retired`

## Scheduling Eligibility

- `AgentDeployment#eligible_for_scheduling?` is the scheduling gate for future
  execution
- a deployment is eligible only when:
  - bootstrap state is `active`
  - health status is `healthy`
  - the logical agent installation is still active
  - the execution environment is still active
  - an active capability snapshot is present
- `Workflows::ResolveModelSelector` rejects future scheduling when the selected
  deployment is no longer eligible

## Audit Scope

- all three lifecycle services write audit rows against the deployment subject
- audit metadata includes the logical agent installation and execution
  environment references
- actor attribution is supported for rotation, revocation, and retirement

## Failure Modes

- rotated credentials stop authenticating immediately after the new digest is
  committed
- revoked credentials stop authenticating before any later re-registration
- retired deployments can still exist as historical rows, but they are not
  eligible for future scheduling

## Retained Implementation Notes

- retirement does not invent a second deployment-retirement state machine; it
  composes the existing `health_status` and `bootstrap_state` models
- scheduling ineligibility is enforced at model-selector resolution time so the
  existing workflow scheduling path inherits the lifecycle gate without adding a
  parallel scheduler abstraction
