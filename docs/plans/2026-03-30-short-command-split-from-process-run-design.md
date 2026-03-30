# Short Command Split From ProcessRun Design

## Goal

Remove short-lived command execution from `ProcessRun` completely so:

- `ProcessRun` only models detached/background runtime resources
- short-lived command execution lives under `AgentTaskRun` / `WorkflowNode`
- short-lived command stdout/stderr stays transport-only and streams to the UI
- long-lived background service lifecycle remains a closable environment resource

## Current Problem

The current model conflates two different lifecycles:

- `ProcessRun(kind = "turn_command")` behaves like node-scoped work that belongs
  to the active turn and should be interrupted with the owning task
- `ProcessRun(kind = "background_service")` behaves like a detached runtime
  resource that may outlive a turn and should be closed through the
  environment-plane close protocol

That split leaks into blockers, turn interruption, close routing, behavior
docs, and tests. It also leaves process-backed workflow nodes only partially
integrated with the node executor.

## Decision

### 1. `ProcessRun` shrinks to detached background services only

- remove `turn_command` from `ProcessRun.kind`
- keep `ProcessRun` as the durable model for environment-owned background
  services
- keep environment-plane close protocol and runtime `process_output` streaming
  only for detached background services

`ProcessRun` may still keep originating workflow/turn provenance, but that is
provenance only, not node-attempt ownership.

### 2. Short-lived commands become tool-invocation sub-execution

- short-lived command execution is modeled as `ToolInvocation(tool_name =
  "shell_exec")`
- the owning durable execution is still `AgentTaskRun`
- the owning scheduler-visible execution is still `WorkflowNode`
- interrupt/close acts on the parent `AgentTaskRun`; the runtime is responsible
  for stopping any in-flight command subprocesses

This matches the Coding-agent pattern more closely than exposing every bounded
command as a separate kernel-owned runtime resource.

### 3. Command stdout/stderr stays transport-only

- add ephemeral runtime events for tool output:
  - `runtime.tool_invocation.output`
- output chunks are not persisted chunk-by-chunk
- the final tool result may still persist structured terminal data in
  `ToolInvocation.response_payload`, but only as summary fields such as exit
  status and byte counts

## Implementation Shape

### Core Matrix

- remove `turn_command` references from:
  - `ProcessRun`
  - blocker queries/snapshots
  - turn-interrupt mainline close requests
  - process close/report tests and docs
- extend execution-report handling so progress events can broadcast
  `runtime.tool_invocation.output`
- keep `ToolInvocation` as the durable audit/result model for short-lived
  commands

### Fenix

- add `shell_exec` to the runtime manifest and tool review allowlist
- execute shell commands inside the agent-task runtime path, not as
  environment-plane runtime resources
- stream stdout/stderr as execution progress reports carrying tool output
- complete the tool invocation with a final structured response payload

## Migration Strategy

Phase 2 is still allowed to make destructive changes.

- rewrite the original workflow/process migrations in place
- regenerate `schema.rb`
- reset local databases as needed
- delete outdated docs and tests rather than preserving compatibility layers

## Invariants

- `WorkflowNode` remains the asynchronous execution boundary
- `AgentTaskRun` remains the mailbox-owned runtime execution aggregate
- `ToolInvocation` is the durable record for short-lived command execution
- `ProcessRun` is reserved for detached/background environment resources only
- command stdout/stderr is transport-only unless explicitly summarized into the
  final tool result
