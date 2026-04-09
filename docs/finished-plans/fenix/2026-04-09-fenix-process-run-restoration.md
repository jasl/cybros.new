# Fenix ProcessRun Restoration

## Task 1

Add failing Fenix-side tests for the restored detached process slice:

- runtime manifest exposes process tools
- system tool registry includes process tools
- program tool executor supports:
  - `process_exec`
  - `process_list`
  - `process_read_output`
  - `process_proxy_info`
- mailbox worker routes `ProcessRun` close requests through a manager instead
  of falling back to `resource_close_failed`

## Task 2

Port the minimal runtime implementation into `agents/fenix`:

- `Fenix::Processes::Launcher`
- `Fenix::Processes::Manager`
- `Fenix::Processes::ProxyRegistry`
- `Fenix::Runtime::ToolExecutors::Process`
- `Fenix::Hooks::ToolResultProjectors::Process`
- system tool registry entries for the four process tools

## Task 3

Align runtime metadata and docs with the restored implementation:

- pairing manifest
- runtime manifest test
- README process surface description

## Task 4

Run the relevant Fenix and CoreMatrix verification, then do review / repair
before returning to the broader contract audit.
