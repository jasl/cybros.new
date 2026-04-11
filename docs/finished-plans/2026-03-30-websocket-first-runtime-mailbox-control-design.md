# WebSocket-First Runtime Mailbox Control Design

## Status

- Date: 2026-03-30
- Status: approved draft
- Scope: `core_matrix` + `agents/fenix`

## Goal

Replace the current `Fenix` Phase 2 execution/debug surface with the real
product execution/control protocol:

- runtime connects outbound to `Core Matrix`
- realtime mailbox delivery over `ControlPlaneChannel` is the primary path
- `poll/report` remains the durable fallback path
- tool side effects are created through machine-facing public APIs before local
  execution begins
- short-lived commands become `CommandRun`-backed task sub-execution under a
  durable `ToolInvocation`
- long-lived processes remain `ProcessRun`-owned environment resources
- `/runtime/executions` is removed as a product path

This follow-up also absorbs the directly relevant command/process portions of:

- [2026-03-30-fenix-runtime-appliance-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/2026-03-30-fenix-runtime-appliance-design.md)
- [2026-03-30-fenix-runtime-appliance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/2026-03-30-fenix-runtime-appliance.md)

Specifically, it absorbs the protocol- and runtime-facing parts of:

- attached command tools (`exec_command`, `write_stdin`)
- long-lived process handling
- machine-facing runtime resource creation APIs
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
  side effects still begin locally before the kernel has a first-class durable
  resource identity for them
- long-lived process close/output now has a runtime-side manager, but there is
  still no public API that lets the runtime ask the kernel to create the
  backing `ProcessRun` before local launch

This leaves four problems:

1. product execution/control is not expressed through one canonical protocol
2. attached command creation is not yet kernel-first, which blocks future
   approval/governance insertion at resource-creation time
3. long-lived process creation is not yet kernel-first, which leaves the
   runtime without a supported way to obtain a `ProcessRun public_id` before
   local launch
4. long-lived process control and short-lived command control are separated in
   the data model but not yet fully separated in runtime integration

## Decision

### 1. Product execution goes through mailbox control only

The canonical product protocol is:

- realtime mailbox delivery over `ControlPlaneChannel`
- fallback mailbox delivery over `POST /agent_api/control/poll`
- runtime reports over `POST /agent_api/control/report`
- machine-facing create APIs for runtime-side durable resources

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

### 3. Kernel-owned resources are created before local side effects begin

`Core Matrix` remains the source of truth for durable side-effect resources.
The runtime must request creation before it starts a local side effect.

The machine-facing API family is:

- `POST /agent_api/tool_invocations`
- `POST /agent_api/command_runs`
- `POST /agent_api/process_runs`

The intent is:

- every tool call that wants first-class governance/audit is materialized as a
  `ToolInvocation`
- every `exec_command` call also materializes a `CommandRun`
- every detached long-lived service also materializes a `ProcessRun`

This keeps approval/governance insertion points on the kernel side instead of
after the runtime has already mutated the environment.

### 4. Short-lived commands are attached task execution, not closable runtime resources

Attached commands adopt Codex-like semantics:

- `exec_command`
- `write_stdin`

Behavior:

- belong to one parent `AgentTaskRun`
- always create a `ToolInvocation`
- always create a `CommandRun`
- may stream stdout/stderr through temporary runtime events
- terminal tool result is durable on the `ToolInvocation`
- session lifecycle is durable on `CommandRun`
- local PTY/session lifecycle is subordinate to the parent task attempt and the
  kernel-owned `CommandRun`
- kernel never creates a `ProcessRun` or close request for attached commands

### 5. Long-lived processes remain environment-plane resources

Long-lived developer services and background processes continue to map to:

- `process_exec`
- `ProcessRun`
- `process_started`
- `process_exited`
- `runtime.process_run.output`
- `resource_close_request`
- `resource_close_acknowledged`
- `resource_closed`
- `resource_close_failed`

They are managed by a distinct runtime-side process manager and never masquerade
as attached command tools. Creation also becomes kernel-first through
`POST /agent_api/process_runs`. The kernel first provisions a `starting`
`ProcessRun`; the runtime then reports `process_started` after the local handle
is live, and later reports `process_exited` if the process terminates without a
close request.

## Architecture

### Core Matrix

`Core Matrix` remains the orchestration truth for:

- mailbox item creation
- delivery routing
- lease ownership and freshness
- workflow and turn lifecycle
- durable audit records
- durable runtime resource creation
- future approval/governance checkpoints

It should not gain a second runtime execution transport.

### Fenix runtime worker

`Fenix` gains a first-class mailbox worker that:

- consumes realtime mailbox deliveries
- falls back to `poll`
- creates local task attempts and local handles only after the kernel has
  returned a durable resource identity
- emits incremental reports
- routes close requests to the right local execution owner

This worker becomes the real runtime entrypoint. It replaces the operational
role of `/runtime/executions`.

### Attached command executor

The attached command executor owns:

- `ToolInvocation` creation request
- `CommandRun` creation request
- local subprocess or PTY startup
- `exec_command`
- `write_stdin`
- stdout/stderr chunking
- local timeout/terminate
- cancellation propagation from the parent task attempt

It never creates `ProcessRun`, and it never starts a local command before the
kernel has returned the `CommandRun public_id`.

### Long-lived process manager

The process manager owns:

- `ProcessRun` creation request
- local handle registry for `ProcessRun`
- output tailing
- close acknowledgement
- terminal close result

It never reports through `ToolInvocation`, and it never starts a local process
before the kernel has returned the `ProcessRun public_id`.

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

`CommandRun` is the durable kernel identity for attached commands.

The runtime still needs one subordinate local session model:

- `open`
- `closing`
- `closed`

`write_stdin` addresses the kernel-owned `CommandRun public_id`; the runtime may
internally maintain a narrower PTY/session id, but that id is not a public
protocol identity.

### Tool invocation

`ToolInvocation` becomes the durable governance/audit wrapper for runtime-side
tool execution:

- `requested`
- `running`
- terminal

Streaming output is optional and transport-only. The durable row keeps the
request, summary result, and governance metadata, not raw streamed bodies.

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

## Creation Semantics

### ToolInvocation creation

Before a runtime-owned tool with first-class governance support begins, the
runtime requests `ToolInvocation` creation from the kernel. This gives the tool
call a durable public identity that future approval/governance can hang from.

### CommandRun creation

Every `exec_command` creates a `CommandRun`, even when the command is one-shot
and non-interactive. That keeps cancellation, PTY, streaming, and future
approvals on one uniform model instead of splitting one-shot and interactive
commands.

### ProcessRun creation

Every detached long-lived service creates a `ProcessRun` before local launch.
The runtime must not start the service first and backfill the durable record
later.

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
- `POST /agent_api/tool_invocations`
- `POST /agent_api/command_runs`
- `POST /agent_api/process_runs`
- `POST /agent_api/control/poll`
- `POST /agent_api/control/report`
- `/cable` `ControlPlaneChannel`

### Remove from product path

- `POST /runtime/executions`
- `GET /runtime/executions/:id`

If a local debug-only execution surface is ever reintroduced, it must be
explicitly documented as debug-only and must not be reused as the product
protocol.

Tool names remain optimized for tool-calling success:

- `exec_command`
- `write_stdin`

The machine-facing public APIs may stay specialized even when the user-facing
tool names remain generic.

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
