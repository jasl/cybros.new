# Fenix ProcessRun Restoration Design

## Decision

`command_run` and `process_run` remain separate runtime abstractions.

- `command_run` means attached, interactive terminal session
- `process_run` means detached, durable background resource

We will not add a detach mode to `exec_command`, and we will not route
`ProcessRun` through the `command_run_*` contract.

## Why

`core_matrix` already models these as different resources:

- `CommandRun`
- `ProcessRun`

They have different lifecycle and control semantics:

- `CommandRun` supports interactive session operations such as `write_stdin`
  and `command_run_wait`
- `ProcessRun` uses durable kernel provisioning plus
  `process_started/process_output/process_exited` and `resource_close_*`

Collapsing them would blur the kernel boundary and make the executor surface
less coherent.

## Fenix Surface To Restore

Restore the detached process executor slice in `agents/fenix`:

- `process_exec`
- `process_list`
- `process_read_output`
- `process_proxy_info`

Restore the local runtime services that make those tools real:

- `Fenix::Processes::Launcher`
- `Fenix::Processes::Manager`
- `Fenix::Processes::ProxyRegistry`
- `Fenix::Runtime::ToolExecutors::Process`
- `Fenix::Hooks::ToolResultProjectors::Process`

## Boundary Rules

### CommandRun

- owns attached shell sessions
- may keep stdin open
- may be waited on interactively
- never emits `process_*` reports
- never stands in for `ProcessRun`

### ProcessRun

- represents durable detached background services
- must be provisioned by `core_matrix` before local launch
- reports `process_started`, `process_output`, and `process_exited`
- is closed through mailbox `resource_close_request` and `resource_close_*`
- does not expose interactive stdin session semantics

## Minimal Modernization

Do not reintroduce the old plugin layer. The new Fenix app no longer has that
abstraction. Restore the process slice directly under the current runtime
service layout.

Also tighten one old behavior while porting:

- `process_exec` should use the `runtime_resource_refs.process_run` supplied by
  `core_matrix`
- do not synthesize fake `process_run_id` values inside Fenix

## Verification Targets

The restored slice is not complete until all of these are true:

- runtime manifest and executor tool catalog expose the process tools
- agent tool execution can launch and inspect owned process runs
- local manager emits the expected `process_*` reports
- mailbox worker can settle `ProcessRun` close requests through the manager
- `core_matrix` and `fenix` contract tests stay green with the restored slice
