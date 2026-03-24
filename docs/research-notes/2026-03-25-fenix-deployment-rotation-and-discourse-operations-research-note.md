# Fenix Deployment Rotation And Discourse Operations Research Note

## Status

Recorded research for future `Fenix` and `Core Matrix` planning.

This note captures the durable operational conclusions that matter for Phase 2.

## Decision Summary

- Do not build a `Fenix` in-place self-updater in Phase 2.
- Model release change as deployment rotation, not runtime mutation.
- Treat `upgrade` and `downgrade` as the same kernel-facing operation.
- If a changed `Fenix` release cannot boot, that boot failure is outside
  `Core Matrix` recovery responsibility.
- Use `Core Matrix` supervision only after a deployment reaches registration and
  healthy runtime participation.

## Stable Findings From Discourse

The most useful operational patterns from the local `discourse` reference are:

- version checking is advisory, not a built-in self-update system
- plugin packages carry lightweight metadata near the package root
- plugin initialization failures are treated as startup blockers
- operational change is applied through restart or rebuild, not hot mutation

Those patterns create a strong bias toward explicit deployment replacement over
runtime self-modification.

## Why Deployment Rotation Fits Fenix Better

`Fenix` is an external agent program consumed by `Core Matrix`, not a module
inside the kernel process. That means the cleanest operational shape is:

- start a new release as a new deployment
- register and handshake it independently
- let `Core Matrix` decide whether future work or paused work can move to it
- stop or retire the old deployment later

This preserves the substrate work already done around:

- heartbeat and health
- capability snapshots
- drift handling
- manual resume and retry
- paused workflow recovery

## Upgrade And Downgrade Rule

From the kernel's perspective, `upgrade` and `downgrade` are symmetrical.

The meaningful questions are:

- did the new deployment boot
- did it register correctly
- does it have a valid capability contract
- is it eligible for cutover or recovery

The kernel should not assign special semantics merely because the release label
went numerically forward or backward.

## Boundary Of Responsibility

The release itself owns:

- boot correctness
- dependency correctness
- local packaging correctness
- whether the runtime can come up at all

`Core Matrix` owns:

- enrollment and registration once the runtime is reachable
- heartbeat and health supervision
- capability drift detection
- routing of paused work into wait, resume, or retry
- auditability of deployment change decisions

## Phase 2 Validation Consequences

Phase 2 should prove all three of these:

- bundled `Fenix` baseline
- independent external `Fenix` pairing
- same-installation deployment rotation across both upgrade and downgrade

That is a better validation target than a richer self-update mechanism because
it directly exercises the existing deployment and recovery substrate.

## Re-Evaluation Triggers

Re-open this note when one of these becomes true:

- `Fenix` needs unattended rollout orchestration
- multiple agent programs need the same release-management semantics
- plugin or extension packaging becomes an active phase
- the product needs a real update UI beyond deployment health and recovery

## Reference Index

These references informed the note, but they are not the source of truth.

Local monorepo references:

- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/discourse/docs/INSTALL-cloud.md](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/discourse/docs/INSTALL-cloud.md)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/discourse/lib/plugin.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/discourse/lib/plugin.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/discourse/lib/discourse_hub.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/discourse/lib/discourse_hub.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/discourse/app/jobs/scheduled/call_discourse_hub.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/discourse/app/jobs/scheduled/call_discourse_hub.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/deployment-bootstrap-and-recovery-flows.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/deployment-bootstrap-and-recovery-flows.md)
- [/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-registration-and-capability-handshake.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-registration-and-capability-handshake.md)
