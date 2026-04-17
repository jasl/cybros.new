# CoreMatrix CLI Gem Rebuild Design

## Goal

Rebuild `core_matrix_cli` as a complete, distributable Ruby gem with a clean
product architecture, a single standard executable entrypoint, and no runtime
dependency on code or files outside the project directory.

This rebuild should preserve the operator-facing product behavior currently
expressed by `core_matrix_cli.old/`, while replacing the legacy structure with
a cohesive standalone CLI product that is easier to distribute, test, and
evolve.

## Scope

This design covers:

- rebuilding `core_matrix_cli/` as the only CLI project
- using `core_matrix_cli.old/` only as a behavior/specification source
- removing `core_matrix_cli.old/` after the new CLI reaches feature parity
- keeping the CLI under the MIT license
- updating monorepo licensing so `core_matrix` remains O'Saasy while the other
  affected non-vendored projects move to or remain on MIT
- collapsing root-only `bin/dev` helper code back into `bin/dev`
- removing the dedicated root test for that helper
- adapting acceptance coverage that currently exercises the CLI so it targets
  the rebuilt gem entrypoint and project layout

This design does not include new CLI features beyond current operator setup
scope.

## Confirmed Constraints

1. `core_matrix_cli/` must be a complete project that does not depend on
   directory-external source files or required documentation at runtime.
2. The only supported development and execution entrypoint is
   `bundle exec exe/cmctl`.
3. No compatibility shim such as `bin/cmctl` should remain after the rebuild.
4. `core_matrix_cli.old/` should be deleted completely after feature parity is
   reached.
5. Product quality and architecture correctness matter more than migration
   speed; a full rebuild is preferred over a direct transplant.
6. Acceptance coverage uses stable repo-root-relative paths for
   `acceptance/` and `core_matrix_cli/`. Future work may rely on that path
   stability explicitly.

## Source of Truth

The rebuilt CLI should treat the following as specification inputs:

- the user-visible command surface and flows in `core_matrix_cli.old/README.md`
- the behavior implied by the existing `core_matrix_cli.old/test/**/*.rb`
  suite
- the current CoreMatrix HTTP API contracts used by the old CLI
- acceptance scenarios that currently invoke the CLI from the repo root

The old implementation files are not the desired architecture and should not be
ported wholesale.

## Architecture Recommendation

Rebuild the CLI around explicit product layers instead of a monolithic Thor
shell:

- `CoreMatrixCLI::CLI`
  - root entrypoint and command registration
- `CoreMatrixCLI::Commands::*`
  - Thor-facing command groups, option parsing, terminal output, exit behavior
- `CoreMatrixCLI::UseCases::*`
  - operator workflows such as login, bootstrap, status, Codex authorization,
    workspace selection, agent attachment, and ingress setup
- `CoreMatrixCLI::CoreMatrixAPI`
  - CoreMatrix HTTP contract adapter expressed as Ruby methods rather than raw
    path assembly at call sites
- `CoreMatrixCLI::State::*`
  - local configuration and credential persistence abstractions
- `CoreMatrixCLI::CredentialStores::*`
  - file-backed and macOS keychain-backed secret persistence
- `CoreMatrixCLI::Support::*`
  - cross-cutting technical helpers such as polling, browser launch, QR
    rendering, clock/sleeper abstractions, and terminal helpers

This structure keeps Thor isolated to CLI presentation concerns and makes the
real product behavior testable without depending on Thor internals.

## Command Boundary

The rebuild should preserve the existing v1 command surface only:

- `init`
- `auth login|whoami|logout`
- `status`
- `providers codex login|status|logout`
- `workspace list|create|use`
- `agent attach`
- `ingress telegram setup`
- `ingress telegram-webhook setup`
- `ingress weixin setup`

The rebuild should not add unrelated administrative breadth during this phase.

Each command object should only:

- parse arguments and options
- call a use case
- render stable operator-facing output
- map domain and transport failures into consistent messages and exit codes

## HTTP Client Decision

Use `Net::HTTP` for the rebuilt client and keep a dedicated CLI-local HTTP
adapter boundary.

Rationale:

- the CLI workload is mostly sequential operator workflow traffic, not a
  concurrent HTTP client workload
- `Net::HTTP` already provides the required timeout and session primitives
- swapping transport stacks during a full architectural rebuild would increase
  migration risk without clear user value
- a dedicated `CoreMatrixAPI` boundary keeps a later `httpx` migration possible
  if real product needs emerge

`httpx` should be considered a future isolated transport decision, not part of
this rebuild.

## Local State Model

The CLI should own its runtime state inside the gem project boundary, while
still storing user-local mutable state in the operator's home directory.

Recommended split:

- `State::ConfigRepository`
  - non-secret JSON state such as base URL, selected workspace, selected
    workspace agent, and selected ingress binding ids
- `State::CredentialRepository`
  - secret-bearing state such as session token
- `CredentialStores::FileStore`
  - default fallback, permission-hardened file write
- `CredentialStores::MacOSKeychainStore`
  - preferred on macOS when available

This keeps the gem self-contained as a product while preserving sane local
operator persistence behavior.

## Documentation Boundary

Anything required to use the CLI must live inside `core_matrix_cli/`.

That means the rebuilt project should keep operator-necessary guidance in one
of:

- `core_matrix_cli/README.md`
- `core_matrix_cli/docs/**`

The CLI should no longer require the operator to jump into
`core_matrix/docs/*` to complete basic CLI-driven setup.

## Error Handling Model

Error behavior should become an explicit contract instead of being scattered
through Thor helpers.

Recommended boundaries:

- `CoreMatrixAPI`
  - maps HTTP responses and transport failures to typed errors
- `UseCases`
  - handles business-path branching and state side effects
- `Commands`
  - turns errors into stable human-readable messages and process exit behavior

The rebuilt CLI should preserve the existing operator UX guarantees:

- unauthorized responses clear the local session and tell the operator to log
  in again
- transport failures report CoreMatrix connectivity problems clearly
- 404 / 422 / 5xx responses remain understandable from the terminal

## Testing Strategy

The rebuild should be test-first and specification-driven.

Recommended test layers:

- command acceptance tests for the public `exe/cmctl` surface
- use case unit tests for workflow sequencing and state transitions
- API/client tests for request building, JSON parsing, timeout handling, and
  error mapping
- state/store tests for config persistence and credential backends
- support tests for polling, browser launching, and QR rendering

`core_matrix_cli.old/test/**/*.rb` should be mined for behavior coverage, but
rewritten to fit the new architecture instead of copied as-is.

High-value old assets such as the fake CoreMatrix server and end-to-end setup
contracts should be retained only if they still express product-level
behavior rather than legacy structure coupling.

## Acceptance Adaptation

Acceptance coverage currently relies on the CLI and must be updated as part of
this rebuild.

Rules for that adaptation:

- acceptance tests may assume stable repo-root-relative paths for
  `acceptance/` and `core_matrix_cli/`
- acceptance entrypoints must switch to the rebuilt executable layout,
  especially `bundle exec exe/cmctl`
- any acceptance helper that references `core_matrix_cli.old/` or `bin/cmctl`
  must be updated or removed
- CLI-related acceptance should continue proving the real operator path rather
  than degrading into unit-only verification

This acceptance work is part of the feature definition, not optional cleanup.

## Licensing Changes

Licensing should become project-explicit and easier to understand:

- `core_matrix/` remains under the O'Saasy License Agreement
- `core_matrix_cli/` remains under MIT
- other affected non-CoreMatrix projects in this monorepo should align with MIT
  in this round where the repository currently implies broader O'Saasy scope
- root licensing text should be updated so it no longer implies that projects
  outside `core_matrix/` inherit O'Saasy by default

Because `agents/fenix/` and `images/nexus/` currently do not have their own top
level license files, this round should add explicit MIT license files there if
the root README is updated to describe them as MIT-licensed projects.

## Root Cleanup

The root helper module `lib/monorepo_dev_environment.rb` exists only to support
`bin/dev` and does not warrant independent product abstraction.

This rebuild should:

- inline the helper logic back into `bin/dev`
- delete `lib/monorepo_dev_environment.rb`
- delete `test/monorepo_dev_environment_test.rb`

That keeps development convenience code lightweight and avoids maintaining
dedicated abstraction and tests for a narrow local script concern.

## Migration Shape

Implementation should follow this high-level order:

1. lock current CLI behavior with new tests in `core_matrix_cli/`
2. rebuild the new CLI architecture inside `core_matrix_cli/`
3. port operator documentation into the new project boundary
4. adapt acceptance coverage to the new executable layout
5. update licensing files and root licensing documentation
6. inline and clean up root `bin/dev` helper code
7. remove `core_matrix_cli.old/` once parity and verification are complete

This order keeps specification pressure high and prevents premature deletion of
the old behavior reference.
