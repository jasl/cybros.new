# Fenix Agent/Executor Role Separation Design

**Date:** 2026-04-10

## Goal

Refactor `agents/fenix` so the cowork runtime is explicitly organized around
three top-level roles:

- `Fenix::Agent`
- `Fenix::ExecutionRuntime`
- `Fenix::Shared`

The intent is to keep all current behavior and external contracts intact while
making the codebase ready for a future physical split between agent and
execution-runtime runtimes.

## Current Findings

The current `agents/fenix` codebase still centers most runtime behavior under
`Fenix::Runtime`, even though the product already exposes two distinct runtime
planes:

- `agent_plane` for agent requests such as `prepare_round`,
  `execute_tool`, and supervision controls
- `executor_plane` for execution-runtime tools such as `exec_command`,
  `process_exec`, and `browser_*`

The most visible mixing points are:

- [`PairingManifest`](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/runtime/pairing_manifest.rb)
- [`MailboxWorker`](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/runtime/mailbox_worker.rb)
- [`ExecuteMailboxItem`](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/runtime/execute_mailbox_item.rb)
- [`SystemToolRegistry`](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/runtime/system_tool_registry.rb)

That structure makes the code harder to review for role violations, makes
future split planning noisy, and keeps role ownership implicit instead of
enforced in the namespace and directory layout.

## Design Direction

### 1. Organize by runtime role, not by historical `runtime` bucket

The primary top-level boundaries should become:

- `Fenix::Agent`
- `Fenix::ExecutionRuntime`
- `Fenix::Shared`

This is not a cosmetic rename. Each namespace must own one clear slice of the
runtime:

- `Agent` owns agent behavior, prompts, skills, memory, and
  supervision/agent requests handling
- `Executor` owns execution-runtime tools, resource lifecycles, and
  command/process/browser execution
- `Shared` owns common protocol, mailbox transport, instrumentation,
  environment/value objects, and other role-neutral foundations

### 2. Enforce one-way dependency flow

The dependency rule is hard and explicit:

- `Fenix::Shared` must not depend on `Fenix::Agent` or `Fenix::ExecutionRuntime`
- `Fenix::Agent` may depend on `Fenix::Shared`
- `Fenix::ExecutionRuntime` may depend on `Fenix::Shared`
- `Fenix::Agent` and `Fenix::ExecutionRuntime` must not depend directly on each other

If coordination is required, it must happen through:

- shared protocol/value objects
- explicit routing/dispatch boundaries
- injected adapters or registries owned by `Shared`

This keeps the code suitable for a future split into separate runtime
processes without another architecture reset.

### 3. Remove the old `Runtime` center of gravity instead of preserving it

This refactor is intentionally destructive. We do not preserve
`Fenix::Runtime::*` as a compatibility namespace.

The preferred end state is:

- old `runtime/*` implementation files are deleted or replaced with thin
  role-neutral routing pieces under `Shared`
- new feature work goes only into `Agent`, `Executor`, or `Shared`
- tests and docs speak only in the new role names

This avoids carrying a second stale abstraction layer after the rewrite.

### 4. Treat Rails autoload boundaries as part of the architecture

This rewrite changes constant ownership and file layout at the same time, so
Zeitwerk correctness is part of the design, not a cleanup detail.

Implementation must ensure:

- namespace names match file paths exactly
- role-owned classes move under role-owned directories
- temporary aliasing is not used to paper over incorrect autoload structure

This keeps the refactor honest and prevents a half-migrated constant graph.

## Proposed Structure

```text
agents/fenix/app/services/
  agent/
    mailbox/
    requests/
    prompts/
    memory/
    skills/
    hooks/
  executor/
    mailbox/
    tools/
    command_runs/
    process_runs/
    browser/
  shared/
    control_plane/
    mailbox/
    manifest/
    protocol/
    instrumentation/
    environment/
    values/
```

The exact subdirectories may be adjusted during implementation, but the role
ownership may not.

## Ownership Mapping

### Agent-owned behavior

The following capabilities belong in `Fenix::Agent`:

- `prepare_round`
- `execute_tool`
- `supervision_status_refresh`
- `supervision_guidance`
- prompt assembly
- memory access
- skills catalog/load/read/install
- agent-facing hooks such as compacting context or deterministic agent helpers

### Executor-owned behavior

The following capabilities belong in `Fenix::ExecutionRuntime`:

- executor tool catalog
- `exec_command` and `command_run_*`
- `process_exec` and `process_*`
- `browser_*`
- command/process/browser registries and managers
- resource-close lifecycle for executor-owned resources

### Shared-owned behavior

The following capabilities belong in `Fenix::Shared`:

- manifest composition
- mailbox envelopes and routing
- control-plane client/report plumbing
- payload/value objects used by both roles
- workspace environment overlay parsing
- protocol constants and shared instrumentation

`execution_assignment` compatibility flow is also best treated as shared
runtime support. It is not cleanly an agent feature or an executor feature and
should remain in a role-neutral shared area unless product requirements change.

## Entry Points

This rewrite must also move the entry points, not just the leaf services.

### Manifest

Manifest generation should be assembled from role-owned fragments:

- `Agent` contributes agent-plane contract and agent tool catalog
- `Executor` contributes execution-runtime-plane tool catalog and resource capabilities
- `Shared` composes the final manifest payload

### Mailbox dispatch

Mailbox routing should become explicit and role-aware:

- `agent_request` routes to `Agent`
- executor tool and resource lifecycle work routes to `Executor`
- role-neutral compatibility work routes to `Shared`

The mailbox router itself should stay in `Shared`, but it should dispatch by
declared ownership, not by a catch-all `Runtime` service that knows everything.

### Jobs and controllers

Related entry points must be moved in the same rewrite:

- controllers
- mailbox execution jobs
- test helpers and acceptance harness adapters
- docs describing runtime planes

Otherwise the directory tree would claim separation while the effective
boundaries stayed mixed in adapters and entrypoints.

## Testing Strategy

Tests must mirror the same role split.

Target structure:

```text
agents/fenix/test/services/
  agent/
  executor/
  shared/
```

The goal is to make role violations obvious in both code review and test
layout.

The rewrite is complete only when:

- existing behavior still passes
- contract coverage still passes
- acceptance suites still pass
- tests no longer rely on `Fenix::Runtime::*` as the primary namespace

## Risks

### 1. Superficial rename without real ownership cleanup

The main failure mode would be moving files but leaving direct cross-role
constant references in place. Review must focus on dependency direction, not
folder names.

### 2. Mailbox ownership drift

`MailboxWorker` and `ExecuteMailboxItem` are currently central mixing points.
If they are not reworked into role-aware routing, the rewrite will only hide
the coupling.

### 3. Manifest drift

The manifest currently declares both runtime planes from one class. The rewrite
must preserve exact external behavior while changing internal ownership.

## Acceptance

The role-separation rewrite is complete when:

- `Fenix::Agent`, `Fenix::ExecutionRuntime`, and `Fenix::Shared` are the active runtime
  namespaces
- the new dependency rule is enforced in code and tests
- current user-facing and agent-facing behavior remains unchanged
- existing runtime contracts still pass
- acceptance suites still exercise the real paths successfully
- runtime docs reflect the new structure without mentioning the old
  `Fenix::Runtime` implementation model as the source of truth
