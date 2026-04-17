# Nexus Runtime Redesign Design

## Goal

Rebuild `execution_runtimes/nexus` as a distributable Ruby gem that starts
with a single operator command, preserves the full current Nexus feature set,
and replaces the legacy Rails-plus-worker topology with a more reliable runtime
kernel that is easier to ship, supervise, and later port to Go or Rust.

## Scope

This design covers:

- rebuilding `execution_runtimes/nexus/` as the only active Nexus project
- treating `execution_runtimes/nexus.old/` as a behavior and capability source,
  not an architecture template
- deleting `execution_runtimes/nexus.old/` after the rebuilt gem reaches full
  functional parity
- redesigning the CoreMatrix execution-runtime protocol where needed instead of
  preserving the current `execution_runtime_api` shape
- keeping Action Cable websocket delivery as the primary low-latency runtime
  path, with poll-based mailbox delivery retained as fallback only
- standardizing the process and TTY runtime contract so CoreMatrix can rely on
  it as a first-class infrastructure surface even when a specific runtime
  disables or does not implement parts of it
- preserving filesystem-backed skills, memory, detached processes, browser
  sessions, and runtime-local resources as Nexus-owned concerns
- using current Ruby 4.0 practice, including `Fiber.scheduler`, where it fits
  the runtime model

This design does not include compatibility shims, migration bridges, or a
phased coexistence strategy with the old Rails implementation.
During implementation, one branch may temporarily carry both the old and new
runtime protocol surfaces until migration tests are green, but the shipped
design still has no long-term coexistence layer.

## Approved Direction

- destructive cleanup is acceptable
- compatibility is not a goal
- full functional parity is required before the old implementation is deleted
- functional parity means the same operator-visible and runtime-visible feature
  surface, not wire compatibility with the old Rails runtime protocol or worker
  topology
- a single operator command matters more than a single OS process
- internal process splitting is acceptable where it materially improves
  reliability
- CoreMatrix protocol changes should be made now rather than deferred if they
  make the runtime boundary cleaner

## Confirmed Constraints

1. `nexus` must remain an execution-runtime-only product. It must not take on
   prompt assembly, profile semantics, or agent business logic.
2. The operator experience after `gem install` must collapse to one standard
   entrypoint such as `nexus run`.
3. Websocket delivery over Action Cable remains the preferred control-plane
   path. Poll delivery is fallback and recovery infrastructure, not the primary
   happy path.
4. Long-lived runtime-owned resources must survive transient control-plane
   failures and produce explainable recovery or cleanup outcomes after runtime
   restart.
5. `CoreMatrix` must remain the source of truth for public identifiers,
   orchestration state, and persistent resource records.
6. The runtime contract for process execution and TTY-backed command sessions
   should become a strong normative contract. Individual runtimes may advertise
   support or disablement, but CoreMatrix should not treat these as ad hoc
   per-runtime inventions.
7. Ruby version targeting should align with the current stable Ruby 4.0 line,
   not speculative 4.1 behavior.

## Source of Truth

The rebuild should treat the following as specification inputs:

- the current Nexus responsibilities and topology documented in
  `execution_runtimes/nexus.old/README.md`
- the current mailbox contract exercised by
  `core_matrix/test/services/agent_control/create_execution_assignment_test.rb`
  and `shared/fixtures/contracts/core_matrix_nexus_execution_assignment.json`
- the current CoreMatrix execution-runtime mediation logic in
  `core_matrix/app/services/provider_execution/tool_call_runners/execution_runtime_mediated.rb`
- the current CoreMatrix execution-runtime API controllers and tests
- the old Nexus process, browser, skills, memory, and control-loop test suites

The old Rails file layout is not the desired target architecture and should not
be ported wholesale.

## Verified Reference Anchors

These anchors were verified against the current repository state on
`2026-04-18`:

- `execution_runtimes/nexus.old/README.md:3-197`
  - current product role, responsibilities, control-plane shape, tool surface,
    worker topology, and deployment assumptions
- `execution_runtimes/nexus.old/app/services/runtime/control_loop.rb:9-105`
  - current websocket-first plus poll-fallback delivery behavior
- `execution_runtimes/nexus.old/app/services/processes/manager.rb:32-260`
  - current detached-process lifecycle, output reporting, close handling, and
    watcher behavior
- `core_matrix/test/services/agent_control/create_execution_assignment_test.rb:54-258`
  - current serialized assignment envelope that Nexus consumes
- `core_matrix/app/services/provider_execution/tool_call_runners/execution_runtime_mediated.rb:15-255`
  - current runtime resource provisioning, envelope construction, and
    reconciliation path
- `core_matrix/app/controllers/execution_runtime_api/control_controller.rb:2-113`
  - current poll and report contract shape
- `core_matrix/app/controllers/execution_runtime_api/command_runs_controller.rb:2-29`
  - current runtime-driven command-run provisioning API
- `core_matrix/app/controllers/execution_runtime_api/process_runs_controller.rb:2-25`
  - current runtime-driven process-run provisioning API
- `core_matrix/app/controllers/execution_runtime_api/attachments_controller.rb:9-75`
  - current attachment request and publish API shape

## Current Problems

The current Nexus shape solved the functional surface but creates deployment and
evolution pressure in the wrong places:

1. the runtime is packaged as a Rails app even though its core job is control
   plane, resource hosting, and local execution
2. operators effectively need a web app plus background-worker topology to
   obtain runtime behavior that conceptually belongs to one appliance
3. runtime reliability currently depends on Rails worker assumptions instead of
   an explicit runtime supervisor model
4. CoreMatrix and Nexus share responsibility awkwardly around `command_runs`
   and `process_runs`, which leads to protocol fragmentation
5. websocket and poll are currently mixed as parallel behaviors instead of one
   canonical mailbox model with a low-latency transport hint
6. process and TTY semantics exist, but they are not yet expressed as a clean
   infrastructure contract that future runtimes can implement consistently

## Target Product Shape

The rebuilt Nexus should be a single-install, single-entry runtime appliance:

- installation artifact: Ruby gem
- operator entrypoint: `nexus run`
- local mutable state root: `NEXUS_HOME_ROOT`, defaulting to `~/.nexus`
- primary responsibility: runtime execution, resource hosting, runtime-local
  skills and memory, control-plane connectivity, and runtime-owned tools

The product promise is:

- one installable runtime package
- one operator command to bring it up
- one managed state root
- automatic supervision and recovery inside the runtime itself

This promise is more important than whether the runtime ultimately uses one OS
process or a small supervised process tree internally.

## Architecture Recommendation

Adopt a single-entry supervisor model with narrow internal fault domains.

### External Shape

`nexus run` should:

- validate configuration and writable state directories
- run local schema migrations for runtime state
- open or refresh the CoreMatrix runtime session
- start the internal runtime roles
- supervise them until shutdown
- expose one consistent readiness and health model

### Internal Roles

The recommended internal roles are:

- `control`
  - owns CoreMatrix session lifecycle
  - owns Action Cable realtime connection
  - owns mailbox pull fallback
  - owns event outbox flush and heartbeat/refresh
- `resource_host`
  - owns detached processes
  - owns TTY-backed command sessions
  - owns browser sessions and other runtime-local handles
  - owns forced cleanup and residual reporting on restart
- `http`
  - exposes `GET /runtime/manifest`
  - exposes local health and diagnostics endpoints
- `browser_host` optional
  - only exists when browser automation is enabled and benefits from stronger
    isolation than the general resource host

These roles must be created and supervised by `nexus run` itself. Operators
must never be required to start a second command manually.

## Concurrency Model

Use Ruby 4.0 as the target line. As of `2026-04-18`, the latest stable release
is Ruby 4.0.2, published on `2026-03-16`.

Ruby 4.0’s scheduler model is useful, but only if applied where it is actually
strong:

- use `Fiber.scheduler` inside the `control` role for HTTP, websocket, sleep,
  timeout, DNS, and other non-blocking control-plane work
- keep the event loop explicit rather than scattering hidden worker pools
- isolate blocking or partly blocking operations behind dedicated adapters or
  dedicated roles
- do not assume all subprocess or PTY behavior becomes magically non-blocking
  by enabling a scheduler

Recommended rules:

- `control` is fiber-first
- `resource_host` is reliability-first
- blocking subprocess, pipe, PTY, or browser-host interactions may use threads
  or helper processes where needed
- all cross-role communication stays local and explicit, preferably via Unix
  domain sockets with framed JSON messages

This keeps Ruby 4.0 features useful without turning them into a design
constraint that fights the OS resource model.

## Durable State Model

Nexus should own a durable runtime journal under `NEXUS_HOME_ROOT`.

Recommended layout:

- `state.sqlite3`
  - runtime sessions
  - mailbox receipts
  - execution attempts
  - resource handles
  - event outbox
  - runtime metadata
- `memory/`
  - filesystem-backed memory store
- `skills/`
  - filesystem-backed skills
- `logs/`
  - operator and diagnostic logs
- `tmp/`
  - transient runtime artifacts

### Required Durable Tables

- `runtime_sessions`
  - session identity, credentials, version fingerprint, last refresh, transport
    hints
- `mailbox_receipts`
  - `item_id + delivery_no` dedupe and lifecycle tracking
- `execution_attempts`
  - `logical_work_id + attempt_no`, current local state, terminal outcome
- `resource_handles`
  - local handles for command sessions, process runs, browser sessions, and
    future runtime-owned resources
- `event_outbox`
  - not-yet-acknowledged events queued for CoreMatrix delivery
- `schema_meta`
  - runtime schema version, build metadata, and housekeeping checkpoints

SQLite should run in WAL mode with short transactions and explicit retry for
busy cases.

## Recovery Model

Startup should follow a fixed recovery order:

1. open state store
2. inspect `resource_handles`
3. reconnect or reap surviving local resources
4. materialize residual outcomes for irrecoverable resources
5. flush `event_outbox`
6. open realtime link
7. resume normal mailbox processing

The runtime should be designed around at-least-once mailbox delivery and
idempotent event submission. Duplicate protection must exist on both sides:

- Nexus dedupes mailbox deliveries locally
- CoreMatrix dedupes event submissions by stable event key

## Control-Plane Model

The canonical control-plane shape should become mailbox-first:

- Action Cable websocket link is the primary low-latency notification path
- websocket messages should mean "work is available" or directly deliver
  mailbox envelopes when available
- `mailbox/pull` remains the canonical recovery and fallback path
- realtime and poll must converge on one mailbox lease model

That means:

- websocket stays required as the preferred path
- poll stays required as fallback
- there is no longer any semantic split between "realtime work" and "poll
  work"

## CoreMatrix API Redesign

The current `execution_runtime_api` should be collapsed into a smaller protocol
surface.

### Keep

- a local Nexus-side `GET /runtime/manifest`
  - operational discovery and diagnostics
- a CoreMatrix attachment-upload or ticket surface
  - file transfer remains distinct from mailbox and event delivery

### Replace With New Runtime Protocol Endpoints

#### `POST /execution_runtime_api/session/open`

Purpose:

- create or resume the runtime session
- rotate credentials
- register the active runtime version package
- return transport and lease hints

This replaces the current split between registration and initial capability
handshake.

#### `POST /execution_runtime_api/session/refresh`

Purpose:

- heartbeat the session
- refresh capabilities or version package when changed
- receive any updated runtime policy from CoreMatrix

This replaces the current `capabilities_controller` split between refresh and
handshake.

#### `POST /execution_runtime_api/mailbox/pull`

Purpose:

- lease mailbox work for the runtime
- act as the canonical fallback and replay path

Mailbox item kinds should remain explicit, including:

- `execution_assignment`
- `resource_close_request`

#### `POST /execution_runtime_api/events/batch`

Purpose:

- submit runtime lifecycle events in batches
- allow idempotent replay
- return per-event acceptance and any immediate follow-up mailbox items

Event families should include:

- `execution_started`
- `execution_progress`
- `execution_complete`
- `execution_fail`
- `execution_interrupted`
- `process_started`
- `process_output`
- `process_exited`
- `resource_close_acknowledged`
- `resource_closed`
- `resource_close_failed`
- future browser and runtime-resource families

### Delete

The following CoreMatrix runtime endpoints should be removed in the redesign:

- `ExecutionRuntimeAPI::RegistrationsController`
- `ExecutionRuntimeAPI::CapabilitiesController`
- `ExecutionRuntimeAPI::ControlController#report` single-event contract
- `ExecutionRuntimeAPI::CommandRunsController`
- `ExecutionRuntimeAPI::ProcessRunsController`

## Resource Identity Model

CoreMatrix should continue to own durable public IDs for `CommandRun`,
`ProcessRun`, and other persistent runtime-facing resources.

The current `ExecutionRuntimeMediated` flow already proves the right general
direction:

- CoreMatrix provisions runtime-facing records and public IDs before runtime
  execution
- the assignment envelope includes `runtime_resource_refs`
- the runtime consumes those refs and reports lifecycle events against them

The redesign should complete that move:

- runtime no longer asks CoreMatrix to create command or process records
- runtime only consumes public resource refs supplied in the assignment
- CoreMatrix remains the sole allocator of durable public IDs

## Standard Runtime Tool Contract

Process and TTY functionality should become a strong infrastructure contract,
not a runtime-specific convention.

Recommended contract families:

- `command_run`
  - `exec_command`
  - `write_stdin`
  - `command_run_wait`
  - `command_run_read_output`
  - `command_run_terminate`
- `process_run`
  - `process_exec`
  - `process_read_output`
  - `process_list`
  - `process_proxy_info`
  - `resource_close_request` semantics for close and kill policy

Design rules:

- schemas and lifecycle semantics are standardized across runtimes
- support is capability-advertised, not hard-assumed
- disabled or unsupported tools fail predictably against the same contract
- CoreMatrix orchestration can safely build generic infrastructure and UI around
  these contracts
- the contract families are intentionally extensible so future runtime-owned
  tools can grow without turning the process and TTY surfaces back into
  per-runtime special cases

This allows future runtimes to opt in or opt out of a tool family while still
sharing one coherent platform surface.

## Attachments

Attachments should be simplified instead of folded awkwardly into the event
batch path.

### Input Attachments

Preferred path:

- include short-lived download descriptors directly in execution snapshot data
  whenever possible
- if a descriptor expires, provide a narrow refresh endpoint rather than a
  broad attachment lookup workflow

### Output Attachments

Keep a dedicated upload or upload-ticket flow:

- runtime uploads files
- CoreMatrix persists them and returns attachment public IDs
- resulting attachment references can then be included in `events/batch`

## Nexus Module Layout

The new gem should expose product-oriented namespaces rather than mimic the old
Rails service tree:

- `CybrosNexus::CLI`
- `CybrosNexus::Config`
- `CybrosNexus::Supervisor`
- `CybrosNexus::State`
- `CybrosNexus::Session`
- `CybrosNexus::Mailbox`
- `CybrosNexus::Events`
- `CybrosNexus::Resources`
- `CybrosNexus::Tools`
- `CybrosNexus::Skills`
- `CybrosNexus::Memory`
- `CybrosNexus::HTTP`

This shape makes the product boundaries explicit and also makes a future
language rewrite easier because the seams are clear.

## Deletion and Cutover Strategy

The cutover should be one-way:

- complete the new gem implementation and protocol changes
- port or rewrite all required tests
- switch CoreMatrix to the new protocol
- remove `execution_runtimes/nexus.old/`
- remove Rails-specific runtime assumptions and documentation

There should be no compatibility layer that tries to keep the old Rails app and
new gem alive together for long-term support.

## Acceptance Criteria

- `execution_runtimes/nexus/` is a real gem product and the only active Nexus
  project
- `execution_runtimes/nexus.old/` is deleted
- the packaged gem can be built and installed into a clean `GEM_HOME`, exposes
  the `nexus` executable, and operators bring the runtime up with `nexus run`
- operators can install Nexus and start it with one command
- Action Cable websocket delivery is active by default and poll remains a
  working fallback path
- runtime restart behavior for detached resources is durable and explainable
- filesystem-backed skills and memory still work
- browser session support still exists, even if internally isolated
- command-run and process-run contracts remain functionally complete and become
  standardized platform surfaces
- CoreMatrix no longer requires runtime-side provisioning endpoints for command
  or process resources
- no runtime-facing API exposes internal bigint IDs

## Verification Requirements

Implementation should not be considered complete until all of the following are
green and inspected:

- the new Nexus gem test suite from `execution_runtimes/nexus/`
- a packaged-gem smoke check that builds the gem, installs it into a clean
  temporary `GEM_HOME`, and verifies the installed `nexus` executable works
- relevant CoreMatrix request, service, and integration tests covering the new
  protocol and envelope shape
- the full `core_matrix` verification suite
- `ACTIVE_VERIFICATION_ENABLE_2048_CAPSTONE=1 bash verification/bin/run_active_suite.sh`
  from the repo root, including inspection of the resulting verification
  artifacts and database state

Staging acceptance must additionally confirm:

- on a clean staging host, `gem install` plus `nexus run` is sufficient to
  bring the runtime up with only the documented environment variables
- runtime session opens and refreshes successfully
- websocket reconnect plus poll fallback recovers from transport interruption
- detached command, process, and browser resources produce sane post-restart
  outcomes
- attachment, skill, and memory flows do not silently corrupt state
- Nexus restart leaves `event_outbox` and `resource_handles` in a sane
  explainable state after recovery

## Open Implementation Biases

The following decisions are intentionally biased for this rebuild and should
not be reopened during implementation without a concrete contradiction:

- choose clean protocol redesign over compatibility
- choose a single operator entrypoint over single-process purity
- choose explicit durable local state over in-memory-only convenience
- choose standardized infrastructure contracts for process and TTY surfaces
- choose websocket-first delivery with poll fallback as a hard requirement
