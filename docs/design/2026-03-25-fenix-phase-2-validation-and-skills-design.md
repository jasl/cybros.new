# Fenix Phase 2 Validation And Skills Design

## Status

Approved focused design for `Fenix` within `Core Matrix` Phase 2.

This document complements the platform-wide phase design. It narrows Phase 2
down to the `Fenix`-specific validation shape, deployment topology, and
agent-program-owned skill boundary.

Implementation status refresh (`2026-03-30`):

- the runtime-surface and external-pairing substrate this design depends on is
  already represented by archived Phase 2 task records
- the `agents/fenix` repository still does not contain the planned skills
  directories, services, or tests, so the skill-compatibility half of this
  design remains greenfield

## Purpose

Use this document to define:

- how `Fenix` proves the Phase 2 loop in real environments
- how external pairing differs from same-installation deployment rotation
- what "upgrade" and "downgrade" mean for an external agent program
- how `Fenix` should support third-party Agent Skills without moving skills
  into the kernel

## Decision Summary

- `Fenix` remains an external agent program. Skills stay on the agent-program
  side and do not become a `Core Matrix` kernel primitive in Phase 2.
- Phase 2 must prove three `Fenix` runtime shapes:
  - bundled baseline
  - independently paired external deployment
  - same-installation deployment rotation
- `upgrade` and `downgrade` use the same runtime model: start another
  deployment, register it, and rotate work to it when policy allows.
- If a new or downgraded `Fenix` release cannot boot, that release failure is
  outside `Core Matrix` recovery scope.
- `Fenix` should behave as an Agent Skills-compatible client for third-party
  skills while still allowing `Fenix`-private system skills.

## Release-Aware Deployment Rotation

Phase 2 should not implement an in-place self-updater for `Fenix`.

Instead, release changes should be modeled as deployment rotation:

- start a new `Fenix` process or container
- register it as a new deployment with its own runtime identity
- let `Core Matrix` supervise realtime link state, control activity, health,
  capability handshake, and recovery eligibility
- cut over future work or recovery-time work to the new deployment
- retire or drain the old deployment

This model applies equally to:

- `upgrade`
- `downgrade`
- same-build restart with a new runtime identity

The exact release signal may reuse `sdk_version` or add a separate
`release_label`, but real validation must distinguish the deployments by
release identity rather than treating them as anonymous restarts.

## Validation Topologies

### Bundled Baseline

`Fenix` must continue proving the default out-of-the-box path:

- bundled bootstrap
- real provider execution
- real tools
- real subagent and human-interaction paths

### Independent External Pairing

Phase 2 must also prove a separately started external `Fenix` deployment:

- enrollment
- registration
- realtime link, control activity, and health
- capability handshake
- bootstrap
- real loop execution

This proves the full external deployment workflow without requiring a second
agent program.

### Same-Installation Rotation

Phase 2 must prove that one logical `AgentInstallation` can host multiple
`Fenix` deployments across release changes.

The validation target is:

- one "old" deployment
- one "new" deployment
- at least one recovery or cutover decision across those deployments
- both `upgrade` and `downgrade` treated as valid release rotation inputs

If a release cannot start or cannot reach healthy registration, the failure is
owned by the release itself rather than by `Core Matrix`.

## Skills Boundary

Skills are an agent-program responsibility in Phase 2.

`Core Matrix` should only see the resulting tool surface exposed by `Fenix`
through capability snapshots, tool binding, invocation audit, and normal policy
gates.

`Core Matrix` does not need a kernel-level skill lifecycle, skill installer, or
skill storage model in this phase.

## Retained Runtime Customization Surface

Removing prompt building from `Core Matrix` should not reduce `Fenix` to one
opaque runtime callback.

Phase 2 should preserve a small `Fenix` runtime surface that remains available
for both code-driven and LLM-driven control paths.

Recommended runtime-stage family:

- `prepare_turn`
- `compact_context`
- `review_tool_call`
- `project_tool_result`
- `finalize_output`
- `handle_error`

Recommended helper family:

- `estimate_tokens`
- `estimate_messages`

These stages and helpers belong on the agent-program side or in a future shared
SDK layer. They are not a reason to move prompt building back into the kernel.

The kernel should instead provide the stable execution context and budget hints
that make these hooks useful:

- execution snapshot identity and transcript context
- model context, including the most likely model or model-profile hint when
  known
- context-window or reserved-output budgeting signals
- hard output-token ceilings when policy exposes them
- advisory compaction-threshold hints
- stable invocation or request correlation ids
- authoritative post-run usage facts for accounting and later adaptive behavior

That preserves customization power without reintroducing the older
prompt-builder-centered architecture.

Expected Phase 2 runtime split:

- `Fenix` may estimate prompt size locally, decide a working budget, and call
  `compact_context` proactively before provider execution
- `Core Matrix` remains the fallback authority for hard ceilings and the keeper
  of authoritative usage facts after the real provider or supervised capability
  returns
- advisory compaction signals based on authoritative post-run provider usage for
  the model execution should feed later `Fenix` behavior, not retroactively
  fail the completed turn

## Compatibility Target

`Fenix` should be compatible with standard third-party Agent Skills.

That means:

- a third-party skill that follows the Agent Skills directory and frontmatter
  conventions should install correctly
- `Fenix` should be able to read, activate, and use that skill's instructions
  and bundled files
- `Fenix` may still define private skills that are not intended to work in
  other clients

The compatibility target is practical interoperability, not strict conformance
to every optional behavior in the upstream reference material.

## Skill Separation Model

`Fenix` should separate skill sources into three classes:

- `skills/.system/<name>/`
  platform-owned built-in skills
- `skills/.curated/<name>/`
  bundled third-party or curated catalog entries
- `skills/<name>/`
  live installed non-system skills inside the active workspace

Rules:

- `.system` skills are reserved and may not be overridden by installed skills
- `.curated` skills act as bundled catalog sources rather than the primary live
  skill root
- live third-party skills become active from `skills/<name>/`
- private `Fenix` system skills are allowed even when they are not portable to
  other clients

## Minimum Skill Surface

Phase 2 should prove one minimal but real skill surface in `Fenix`:

- `skills_catalog_list`
- `skills_load`
- `skills_read_file`
- `skills_install`

That surface should be sufficient to:

- discover bundled curated skills
- discover installed live skills
- load and read installed skill content
- install third-party skills from a supported source

Phase 2 does not require:

- a plugin marketplace
- a hot-reload skill runtime
- same-turn skill mutation taking effect immediately

## Installation Rules

Skill installation in `Fenix` should follow these safety rules:

- install through staging rather than writing directly into the live skill root
- validate the fetched or staged skill root before promotion
- reject installs that collide with `.system` skill names
- record provenance for installed third-party skills
- keep replacement cheap by snapshotting the old live skill before overwrite
- make newly installed or replaced skills effective on the next top-level turn

## Phase 2 Manual Validation Matrix

The manual validation set for `Fenix` should include all of the following:

- bundled `Fenix` default assistant loop
- external `Fenix` enrollment and pairing
- same-installation deployment rotation across release change
- one explicit downgrade rotation
- one code-driven or mixed code-plus-LLM path, not just pure LLM control
- one built-in system skill that deploys another agent
- install and use a third-party Agent Skills package from
  [obra/superpowers](https://github.com/obra/superpowers)
- one wait-state handoff where `Fenix` requests a kernel-owned blocking
  resource and the workflow later resumes cleanly
- one stale-work scenario where newer input safely supersedes or queues older
  execution without letting the older result become authoritative

The built-in deployment skill should exist to prove that `Fenix` can use its
own system-skill mechanism for an operational workflow, not just for passive
instruction loading.

## Out Of Scope

This design does not require:

- a `Fenix` self-update daemon
- a kernel-level skills subsystem
- plugin packaging or marketplace support
- completion-surface standardization
- guaranteeing that every boot failure from a changed `Fenix` release can be
  recovered automatically

## Related Documents

- [2026-03-25-core-matrix-platform-phases-and-validation-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md)
- [2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md)
- [2026-03-25-fenix-skills-and-agent-skills-spec-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-fenix-skills-and-agent-skills-spec-research-note.md)
- [2026-03-25-fenix-deployment-rotation-and-discourse-operations-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-fenix-deployment-rotation-and-discourse-operations-research-note.md)
