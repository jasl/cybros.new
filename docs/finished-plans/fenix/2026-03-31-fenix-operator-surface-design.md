# Fenix Operator Surface Design

## Status

- Date: 2026-03-31
- Status: approved draft
- Execution status: ready to execute from the current post-appliance baseline

## Goal

Turn the current `agents/fenix` runtime into a coherent operator workspace for
humans and agent programs by organizing the existing environment capabilities
around a small set of first-class operational objects instead of a flat tool
catalog.

This follow-up should make the runtime easier to understand and drive without
changing the durable kernel truth that already lives in Core Matrix.

## Current Constraints

- `core_matrix` already owns the durable runtime identities for side effects:
  - `ToolInvocation`
  - `CommandRun`
  - `ProcessRun`
- `agents/fenix` already exposes a stable runtime appliance baseline with:
  - websocket-first mailbox control
  - `.fenix` workspace bootstrap
  - `exec_command`, `write_stdin`, and `process_exec`
  - browser, web, workspace, and memory tools
  - fixed-port process proxy support
- the current manifest and plugin registry expose the right raw capabilities,
  but the operator-facing shape is still broad and flat
- discoverability is inconsistent:
  - some capabilities are object-oriented (`CommandRun`, `ProcessRun`)
  - some are file-oriented (`workspace_read`, `workspace_write`)
  - some are session-oriented (`browser_*`)
- mutation semantics are intentionally split:
  - detached process close remains kernel-driven through `resource_close_*`
  - attached command control remains runtime-local and must still reconcile
    through the existing `CommandRun` and `ToolInvocation` contracts

## High-Level Decision

Build the next Fenix follow-up as a **resource-first operator surface**.

The main operator objects should be:

- `workspace`
- `memory`
- `command_run`
- `process_run`
- `browser_session`

The runtime should keep the current external tool names where they already
exist, but it should regroup the catalog and add missing helper tools so each
operator object can be explored and controlled through one coherent family.

This work belongs primarily in `agents/fenix`, not `core_matrix`.
Core Matrix already provides the right durable identities for the current
generation of runtime side effects. The follow-up here is to make those
capabilities usable and internally consistent on the runtime side.

## Operator Objects

### Workspace

The workspace surface should be about navigation and bounded file operations,
not about making the model guess the filesystem layout from raw paths.

Recommended shape:

- keep:
  - `workspace_read`
  - `workspace_write`
- add:
  - `workspace_tree`
  - `workspace_find`
  - `workspace_stat`

Expected behavior:

- all paths remain rooted under `/workspace`
- listing/tree operations are bounded and summarized
- find operations remain text-oriented and avoid shelling out unless necessary
- file metadata is available without forcing a full read

### Memory

The memory surface should reflect the OpenClaw-style split already introduced
into `.fenix`:

- root/bootstrap overlays
- conversation-scoped overlays
- daily/non-injected memory notes

Recommended shape:

- keep:
  - `memory_get`
  - `memory_search`
  - `memory_store`
- add:
  - `memory_list`
  - `memory_append_daily`
  - `memory_compact_summary`

Expected behavior:

- operators can inspect what memory exists before writing more
- daily/raw memory stays separate from always-injected memory
- summarization writes back into `.fenix` rather than living only in transient
  execution payloads

### CommandRun

Attached commands are already modeled correctly at the kernel boundary. The
missing piece is an operator surface that treats them as running sessions, not
only as a side effect of one tool call.

Recommended shape:

- keep:
  - `exec_command`
  - `write_stdin`
- add:
  - `command_run_wait`
  - `command_run_read_output`
  - `command_run_terminate`
  - `command_run_list`

Expected behavior:

- all `exec_command` calls still create `CommandRun`
- streamed stdout/stderr remains ephemeral and user-facing
- terminal summaries remain compact
- explicit wait/read/terminate helpers remove the need for prompt-side polling
  hacks

### ProcessRun

Detached services remain execution-plane resources aligned with
Core Matrix `ProcessRun`.

Recommended shape:

- keep:
  - `process_exec`
- add:
  - `process_list`
  - `process_read_output`
  - `process_proxy_info`

Expected behavior:

- detached services can be discovered and inspected from the runtime side
- close remains kernel-driven
- proxy metadata is surfaced directly instead of being reconstructed by prompt
  logic

### BrowserSession

Browser tools already form a useful family, but they still lack the same
discoverability and inspection ergonomics expected from other operator objects.

Recommended shape:

- keep:
  - `browser_open`
  - `browser_navigate`
  - `browser_get_content`
  - `browser_screenshot`
  - `browser_close`
- add:
  - `browser_list`
  - `browser_session_info`

Expected behavior:

- operators can recover what browser sessions are open
- current URL, title, and recent navigation state can be inspected without
  taking a screenshot or dumping full HTML

## Catalog And Manifest Shape

The pairing manifest should keep its existing raw tool catalog, but it should
also expose operator-friendly grouping metadata.

Recommended additions:

- operator groups:
  - `workspace`
  - `memory`
  - `command_run`
  - `process_run`
  - `browser_session`
- per-tool annotations:
  - `operator_group`
  - `resource_identity_kind`
  - `mutates_state`
  - `supports_streaming_output`

This should be additive. The existing `tool_catalog` and
`executor_tool_catalog` stay stable so Core Matrix integration does not need
to be redesigned.

## Prompt And Context Strategy

The operator surface should not rely only on manifest metadata. The runtime
should also assemble a small operator-oriented context layer for the main
conversation path.

Recommended additions:

- a built-in operator guidance prompt fragment, for example `prompts/OPERATOR.md`
- a generated operator snapshot under:
  - `.fenix/conversations/<public_id>/context/operator_state.json`
- prompt-time summaries for:
  - active `CommandRun`
  - active `ProcessRun`
  - active browser sessions
  - workspace root highlights
  - memory inventory

This snapshot is a runtime-local convenience layer, not a new durable source of
truth. It should be treated as a readable projection of existing runtime state.

## Runtime-Local State Model

Fenix should continue to treat local handles and registries as projections, not
facts. This follow-up may add lightweight local indexes for discoverability, but
it should not pretend that runtime-local records are authoritative over the
operating system or the kernel.

Invariants:

- Core Matrix remains the durable source of truth for `ToolInvocation`,
  `CommandRun`, and `ProcessRun`
- Fenix local registries may be in-memory or lightweight on-disk projections
- browser session and command-process inspection data may be cached locally for
  operator UX
- cache loss is acceptable as long as terminal reports and lost-session behavior
  reconcile correctly

## Out Of Scope

This follow-up should not absorb two other worthwhile tracks:

- richer plugin ecosystem work
  - third-party plugin lifecycle
  - healthcheck/bootstrap execution contracts
  - workspace-loaded plugin security policy
- approval and governance work
  - selective approval gates
  - runtime-local permission policy
  - command/process/browser governance profiles

Those should be recorded separately under `docs/future-plans`.

## Verification Strategy

The operator surface should be treated as a product workflow, not only a test
fixture.

Required verification layers:

1. integration tests for each operator family
2. manifest/pairing tests for grouping metadata
3. command/process/browser lifecycle tests for new inspection helpers
4. real runtime smoke scripts that exercise:
   - workspace browsing
   - memory inventory and writeback
   - interactive `CommandRun`
   - detached `ProcessRun` inspection
   - browser session inspection

## Related Documents

- [2026-03-30-fenix-runtime-appliance-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/2026-03-30-fenix-runtime-appliance-design.md)
- [2026-03-30-fenix-runtime-appliance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/2026-03-30-fenix-runtime-appliance.md)
- [agent-runtime-resource-apis.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-runtime-resource-apis.md)
- [workflow-artifacts-node-events-and-process-runs.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md)
