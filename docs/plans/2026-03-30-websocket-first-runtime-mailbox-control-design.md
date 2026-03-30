# WebSocket-First Runtime Mailbox Control Design

## Status

- Date: 2026-03-30
- Status: approved draft
- Scope: `core_matrix` + `agents/fenix`

## Goal

Replace the current `Fenix` Phase 2 execution/debug surface with the real
product execution/control protocol:

- runtime connects outbound to `Core Matrix`
- realtime mailbox delivery over `AgentControlChannel` is the primary path
- `poll/report` remains the durable fallback path
- short-lived commands become attached task sub-execution
- long-lived processes remain `ProcessRun`-owned environment resources
- `/runtime/executions` is removed as a product path

This follow-up also absorbs the directly relevant command/process portions of:

- [2026-03-30-fenix-runtime-appliance-design.md](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/docs/plans/2026-03-30-fenix-runtime-appliance-design.md)
- [2026-03-30-fenix-runtime-appliance.md](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/docs/plans/2026-03-30-fenix-runtime-appliance.md)

Specifically, it absorbs the protocol- and runtime-facing parts of:

- attached command tools (`exec_command`, `write_stdin`)
- long-lived process handling
- runtime-side worker/executor structure

It does **not** absorb the broader runtime appliance scope such as plugin
ecosystem, Ubuntu packaging, browser/web tooling, `.fenix` workspace layout,
or fixed-port proxying.

## Problem

The current Phase 2 system validated the domain model, but the deployed runtime
path is still split:

- `Core Matrix` product control uses mailbox items, realtime delivery, poll,
  and report
- `Fenix` still has `/runtime/executions` as a local execution surface
- manual validation had to bridge into `/runtime/executions` instead of using
  only the real mailbox control plane
- short-lived commands were recently split out of `ProcessRun`, but runtime
  cancellation still stops at the parent task boundary rather than flowing
  through a first-class runtime worker contract

This leaves three problems:

1. product execution/control is not expressed through one canonical protocol
2. attached command cancellation is not modeled through a true runtime worker
   and local execution-handle registry
3. long-lived process control and short-lived command control are separated in
   the data model but not yet fully separated in runtime integration

## Decision

### 1. Product execution goes through mailbox control only

The canonical product protocol is:

- realtime mailbox delivery over `AgentControlChannel`
- fallback mailbox delivery over `POST /agent_api/control/poll`
- runtime reports over `POST /agent_api/control/report`

`/runtime/executions` is removed as a product path.

`/runtime/manifest` stays as the registration/capability surface.

### 2. Runtime connects outbound; the kernel does not rely on runtime callback HTTP

`Core Matrix` should not depend on callback HTTP into runtime-private
addresses. That conflicts with:

- home/self-hosted deployments
- private subnets
- container or tailnet-only exposure

The runtime therefore owns the outbound link:

- realtime via WebSocket
- fallback via poll

This is already aligned with:

- [agent-registry-and-connectivity-foundations.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md)
- [agent-runtime-resource-apis.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-runtime-resource-apis.md)

### 3. Short-lived commands are attached task execution, not closable runtime resources

Attached commands adopt Codex-like semantics:

- `exec_command`
- `write_stdin`

Behavior:

- belong to one parent `AgentTaskRun`
- stream stdout/stderr through temporary runtime events
- terminal result is durable as one `ToolInvocation`
- local session lifecycle is subordinate to the parent task attempt
- kernel never creates a `ProcessRun` or close request for attached commands

### 4. Long-lived processes remain environment-plane resources

Long-lived developer services and background processes continue to map to:

- `ProcessRun`
- `runtime.process_run.output`
- `resource_close_request`
- `resource_close_acknowledged`
- `resource_closed`
- `resource_close_failed`

They are managed by a distinct runtime-side process manager and never masquerade
as attached command tools.

## Architecture

### Core Matrix

`Core Matrix` remains the orchestration truth for:

- mailbox item creation
- delivery routing
- lease ownership and freshness
- workflow and turn lifecycle
- durable audit records

It should not gain a second runtime execution transport.

### Fenix runtime worker

`Fenix` gains a first-class mailbox worker that:

- consumes realtime mailbox deliveries
- falls back to `poll`
- creates local task attempts and local process handles
- emits incremental reports
- routes close requests to the right local execution owner

This worker becomes the real runtime entrypoint. It replaces the operational
role of `/runtime/executions`.

### Attached command executor

The attached command executor owns:

- local subprocess or PTY startup
- `exec_command`
- `write_stdin`
- stdout/stderr chunking
- local timeout/terminate
- cancellation propagation from the parent task attempt

It never creates `ProcessRun`.

### Long-lived process manager

The process manager owns:

- local handle registry for `ProcessRun`
- output tailing
- close acknowledgement
- terminal close result

It never reports through `ToolInvocation`.

## State Model

### Mailbox item

- `queued`
- `leased` / `acked`
- terminal

This remains the `Core Matrix` durable control-plane state.

### Task attempt

The runtime needs a local state model for mailbox-owned task execution:

- `queued`
- `running`
- `closing`
- terminal

This is runtime-local operational state, not a new kernel aggregate.

### Attached command session

Attached command sessions are runtime-local and subordinate:

- `open`
- `closing`
- `closed`

They are referenced by runtime-issued session ids for `write_stdin`, not by
kernel-owned public ids.

### Process handle

Long-lived process handles are runtime-local projections of `ProcessRun`:

- `running`
- `closing`
- `closed`
- `failed`

## Cancel And Close Semantics

### AgentTaskRun close

Close starts with:

- `resource_close_request(resource_type = AgentTaskRun, ...)`

Runtime behavior:

1. acknowledge close
2. move the local task attempt to `closing`
3. propagate stop to attached sub-executions
4. emit the execution terminal report for the task attempt
5. emit terminal `resource_close_*` for the parent task resource

The split is intentional:

- `execution_*` reports describe the task execution outcome
- `resource_close_*` reports describe close-control settlement of the closable
  parent resource

### ProcessRun close

Long-lived process close stays environment-plane:

1. receive `resource_close_request(resource_type = ProcessRun, ...)`
2. acknowledge close
3. stop the local process
4. emit any final `runtime.process_run.output`
5. emit `resource_closed` or `resource_close_failed`

No `execution_*` reports are involved.

## Transport Rules

- realtime push is preferred whenever the runtime has an open control link
- fallback polling must be semantically equivalent to realtime delivery
- duplicate or stale delivery remains constrained by the existing mailbox lease
  and freshness contract
- runtime output streaming remains transport-only:
  - attached command output: `runtime.tool_invocation.output`
  - process output: `runtime.process_run.output`

## API Surface

### Keep

- `GET /runtime/manifest`
- `POST /agent_api/control/poll`
- `POST /agent_api/control/report`
- `/cable` `AgentControlChannel`

### Remove from product path

- `POST /runtime/executions`
- `GET /runtime/executions/:id`

If a local debug-only execution surface is ever reintroduced, it must be
explicitly documented as debug-only and must not be reused as the product
protocol.

## Verification

### Automated

Must cover:

1. realtime `execution_assignment` delivery
2. poll fallback delivery
3. running attached command interrupted through parent `AgentTaskRun` close
4. long-lived `ProcessRun` close via environment-plane close control
5. durable state alignment after execution/close reports

### Manual / proof-based

The follow-up must also ship real operator-style validation, not only tests.

Minimum manual proof set:

1. bundled runtime + realtime assignment execution
2. external runtime + realtime assignment execution
3. realtime disconnect + poll fallback execution
4. provider-backed execution through the real runtime control plane
5. running `exec_command` interrupted through turn interrupt
6. long-lived `ProcessRun` closed through close control

Proof artifacts must record only `public_id` identifiers and must include:

- conversation public id
- turn public id
- workflow run public id
- expected DAG shape
- observed DAG shape
- expected lifecycle state
- observed lifecycle state

## Documentation Replacement

The implementation must update or replace the product-facing execution story in:

- [agent-runtime-resource-apis.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-runtime-resource-apis.md)
- [agent-registry-and-connectivity-foundations.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md)
- [workflow-artifacts-node-events-and-process-runs.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md)
- [workflow-scheduler-and-wait-states.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md)
- [agents/fenix/README.md](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/README.md)

It must also amend the relevant runtime appliance planning docs so they refer to
the new mailbox-first runtime worker shape rather than the old execution
surface.

## Out Of Scope

This follow-up does not include:

- generic plugin registry rollout
- runtime packaging/distribution work
- `.fenix` workspace state and memory overlays
- browser automation
- web tooling
- Firecrawl integration
- fixed-port dev proxy

Those can build on top of this protocol once runtime execution/control is
stable.
