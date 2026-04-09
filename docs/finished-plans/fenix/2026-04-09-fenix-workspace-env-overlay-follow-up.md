# Fenix Workspace Env Overlay Follow-Up

## Status

Implemented on `2026-04-09` in `agents/fenix`.

## Why This Exists

Current `agents/fenix` only supports runtime-level environment variables:

- host/container `ENV`
- runtime bootstrap additions such as managed Python under `FENIX_HOME_ROOT`

Execution tools inherit that runtime process environment. The current runtime
does **not** support workspace-scoped environment overrides, and it no longer
carries the old `conversation`-scoped overlay shape.

This document records the clean future design for a **workspace-only** env
overlay.

## Product Goal

Add a workspace-scoped environment overlay that:

- is local to one workspace
- affects execution tools only
- does not mutate global process `ENV`
- does not introduce conversation-level env state
- does not blur runtime secrets with project execution settings

## Business Behavior

The intended user-visible behavior is:

- when a workspace contains `.fenix/workspace.env`, `exec_command` sees those
  variables in the child process
- when a workspace contains `.fenix/workspace.env`, `process_exec` sees those
  variables in the child process
- if `.fenix/workspace.env` is absent, execution behaves exactly as it does now
- if `.fenix/workspace.env` is invalid, the execution request fails cleanly
  with the same tool/runtime validation error family used for other execution
  input errors
- workspace overlay affects only the workspace that owns the file
- workspace overlay does not affect Rails boot, control-plane wiring, mailbox
  workers, browser host startup, or skill repository scope

## Non-Goals

- no conversation-scoped `.env`
- no agent-program-version-scoped `.env`
- no implicit loading of project-root `.env`
- no global mutation of Rails/Fenix process `ENV`
- no browser-host env overlay in the first cut
- no general-purpose "edit any runtime secret from the conversation" feature
- no change to existing `process_exec` working-directory semantics in the first
  cut

## Source Of Truth

Use exactly one reserved workspace file:

- `.fenix/workspace.env`

Do not read:

- project-root `.env`
- project-root `.env.agent`
- `.fenix/conversations/...`
- `.fenix/agent_program_versions/...`

That keeps the feature explicit and avoids accidentally importing the user's
application secrets or local app config.

## Parsing Rules

`workspace.env` should use a strict, simple parser:

- allow blank lines
- allow `#` comments
- allow optional `export ` prefix
- allow only `KEY=VALUE` lines
- no variable interpolation
- no command substitution
- no multiline values
- no shell evaluation

Accepted keys should match:

- `\A[A-Z][A-Z0-9_]*\z`

Invalid lines should fail closed with a structured validation error.

## Merge Semantics

Execution-time environment should be built as:

1. runtime baseline `ENV`
2. workspace overlay from `.fenix/workspace.env`

Overlay wins only for allowed keys.

This merge must happen per execution request and must be passed explicitly to
subprocess launch APIs. The merged hash must not be written back into global
`ENV`.

## Allowed Scope

First cut should apply the merged env only to:

- `exec_command`
- `process_exec`

It should not apply to:

- Rails boot
- control-plane clients
- mailbox workers
- browser host
- skill installation/repository scope

This keeps the feature about workspace execution, not runtime identity.

## Reserved Keys

The first cut should reject overlay entries for runtime-owned or secret-bearing
keys, including:

- `CORE_MATRIX_*`
- `SECRET_KEY_BASE`
- `ACTIVE_RECORD_ENCRYPTION__*`
- `RAILS_ENV`
- `DATABASE_URL`
- `BUNDLE_GEMFILE`
- `BUNDLE_PATH`
- `FENIX_HOME_ROOT`
- `FENIX_PYTHON_ROOT`
- `FENIX_PYTHON_INSTALL_ROOT`
- `UV_PYTHON_INSTALL_DIR`
- `PLAYWRIGHT_BROWSERS_PATH`
- `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`
- `PATH`

The goal is to allow project execution settings, not runtime rewiring.

## Runtime Shape

The implemented internal shape is:

- `WorkspaceEnvOverlay`
  - loads and validates `.fenix/workspace.env`
- execution tool runners
  - resolve `workspace_root` from execution context
  - build `merged_env = ENV.to_h.merge(workspace_env_overlay)`
  - pass `merged_env` explicitly into subprocess launch APIs

The first cut keeps overlay resolution inside the execution tool boundary so an
invalid workspace overlay does not break unrelated runtime paths such as
`prepare_round`.

## Expected File Touches

The implementation surface is:

- a new
  `agents/fenix/app/services/fenix/runtime/workspace_env_overlay.rb`
  service
- `agents/fenix/app/services/fenix/runtime/tool_executors/exec_command.rb`
- `agents/fenix/app/services/fenix/runtime/tool_executors/process.rb`
- `agents/fenix/app/services/fenix/processes/launcher.rb` or
  `agents/fenix/app/services/fenix/processes/manager.rb`
- focused tests under `agents/fenix/test/services/fenix/...`
- integration coverage under `agents/fenix/test/integration/...`

The goal is to keep the feature self-contained inside `agents/fenix`.

## Implementation Order

1. Add `WorkspaceEnvOverlay` parsing and validation with unit tests.
2. Inject merged env into `exec_command` child processes.
3. Inject merged env into `process_exec` child processes.
4. Add regression coverage proving global `ENV` stays unchanged.
5. Add negative coverage for invalid files and reserved keys.
6. Run focused tests, full `agents/fenix` verification, then review/repair.

## Error Handling

If `.fenix/workspace.env` is absent:

- treat as empty overlay

If the file exists but is invalid:

- fail the execution request with the normal tool/runtime validation error
  envelope
- do not partially apply valid-looking lines

If a reserved key appears:

- reject the overlay as invalid
- do not silently drop the key

## Acceptance Criteria

This follow-up is complete only when all of the following are true:

- `exec_command` sees allowed workspace overlay variables
- `process_exec` sees allowed workspace overlay variables
- absent overlay file is a no-op
- invalid syntax fails cleanly
- reserved keys fail cleanly
- browser host behavior is unchanged
- global `ENV` in the Rails/Fenix process is unchanged after execution
- one workspace's overlay does not affect another workspace

## Verification Gate

At minimum, implementation closeout should include:

```bash
cd agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
```

Focused tests should also exist for:

- parser success cases
- parser failure cases
- reserved-key rejection
- `exec_command` env visibility
- `process_exec` env visibility
- no global `ENV` mutation
- no browser overlay leakage

## Manual Acceptance

The manual smoke path should prove:

1. Create a disposable workspace with `.fenix/workspace.env` containing one
   allowed key such as `HELLO=workspace`.
2. Run `exec_command` in that workspace and verify the child process sees
   `HELLO=workspace`.
3. Run `process_exec` in that workspace, then verify through
   `process_read_output` or the terminal process report that the child process
   saw `HELLO=workspace`.
4. Repeat from a second workspace without the file and verify `HELLO` is not
   present.
5. Replace the file with a reserved key such as `PATH=/tmp/fake` and verify the
   request fails instead of partially applying the file.

## Design Rationale

This design keeps the architecture clean:

- runtime env remains deployment-owned
- workspace overlay remains execution-owned
- conversation state remains separate
- no hidden coupling to project-root `.env`
- no accidental leakage of runtime secrets into user-controlled workspace files

If a future product need appears for conversation-level env state, that should
be designed as a separate feature rather than layered onto this workspace
overlay.
