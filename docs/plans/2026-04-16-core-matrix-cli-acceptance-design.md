# CoreMatrix CLI Acceptance Design

## Goal

Use `core_matrix_cli` as the black-box operator surface for acceptance setup
without replacing the existing product-proof acceptance harness.

The concrete target is:

- add a dedicated CLI operator smoke lane
- switch the `2048 capstone` setup phase to `cmctl`
- keep the existing capstone final proof, artifact inspection, and database
  audit path unchanged

## Problem

`core_matrix_cli` now covers the operator setup path, but acceptance still
bootstraps CoreMatrix through direct Rails/service helpers. That leaves two
problems:

1. the CLI is tested mostly at unit/contract level, not against the real local
   stack
2. the capstone setup path and the operator setup path can drift because they
   use different entrypoints

At the same time, replacing the whole capstone with CLI-driven orchestration
would be the wrong boundary. `cmctl` is an operator surface; it should not
become the primary proof surface for conversation execution, attachment
publication, or runtime state inspection.

## Recommendation

Adopt a hybrid structure:

- **CLI-owned setup**
  - installation bootstrap and operator login
  - workspace selection persistence
  - workspace-agent selection persistence
  - readiness/status inspection
- **Harness-owned final proof**
  - runtime registration and app-api roundtrip orchestration
  - conversation export/debug export inspection
  - 2048 artifact validation
  - database shape and state-flow audit

This keeps the `CoreMatrix / Agent / ExecutionRuntime` boundary clean:

- `core_matrix_cli` proves the operator HTTP surface
- the acceptance harness still proves the product runtime loop

## Scope

### In scope

- new acceptance helper for invoking `cmctl` against the local stack
- isolated CLI config/credential storage for automation runs
- optional browser suppression / file-store forcing for automation
- a dedicated CLI operator smoke scenario
- capstone setup-phase migration to CLI
- review artifacts/evidence showing the CLI steps and resulting selection state

### Out of scope

- replacing capstone final proof with CLI
- driving Telegram or Weixin setup in acceptance
- adding real webhook or QR human-loop validation to automation
- turning acceptance into a generic CLI-only orchestration harness

## Design

### 1. Add automation-safe CLI runtime knobs

Acceptance must be able to run `cmctl` without touching the real user
environment.

`core_matrix_cli` should support environment-driven overrides for:

- config path
- credential store mode and path
- browser launching

Recommended contract:

- `CORE_MATRIX_CLI_CONFIG_PATH`
- `CORE_MATRIX_CLI_CREDENTIAL_STORE=file|keychain`
- `CORE_MATRIX_CLI_CREDENTIAL_PATH`
- `CORE_MATRIX_CLI_DISABLE_BROWSER=1`

These are automation knobs only. They do not change the operator-facing CLI
contract.

### 2. Add an acceptance-owned CLI runner

The acceptance harness should gain a small helper that:

- prepares an isolated CLI home/config/credential directory under the run
  artifact root
- runs `bundle exec ./bin/cmctl ...`
- provides scripted stdin for prompt-driven commands
- captures stdout/stderr/exit status as evidence
- exposes parsed config and credential payloads back to Ruby scenarios

This helper belongs in `acceptance/lib`, not in `core_matrix_cli`.

### 3. Add a standalone CLI operator smoke lane

Create one new acceptance scenario whose purpose is only to prove the black-box
operator path.

The lane should cover:

- `cmctl init`
- `cmctl status`
- `cmctl workspace create`
- `cmctl workspace use`
- `cmctl agent attach`

It should not cover Telegram/Weixin setup, and it does not need to prove a
full conversation turn.

The scenario may use acceptance-owned backend helpers to discover stable public
ids such as the bundled agent id; that does not violate the boundary because the
proof target is still the CLI command contract, not a pure end-user manual flow.

### 4. Switch capstone setup phase to CLI

The capstone should move only its operator-owned setup to `cmctl`:

- bootstrap/login via `cmctl init`
- post-registration refresh via `cmctl init` or `cmctl status`
- selection state sourced from CLI config/credentials

The capstone should continue to use acceptance-owned helpers for:

- bundled agent/runtime registration
- bring-your-own runtime registration
- app-api conversation creation
- transcript/export/debug-export/download/database verification

This produces a stronger hybrid proof:

- the setup path is now the real CLI
- the final proof remains the real product loop

### 5. Preserve current acceptance ownership of runtime proof

Do not route conversation creation, turn polling, attachment download, export,
or database inspection through `cmctl`.

Those are not operator setup concerns, and moving them would make failures
harder to localize.

## Evidence And Artifacts

Both the new smoke lane and the capstone should write CLI evidence under the
artifact bundle, for example:

- `evidence/cli/init.stdout.txt`
- `evidence/cli/init.stderr.txt`
- `evidence/cli/status.stdout.txt`
- `evidence/cli/config.json`
- `evidence/cli/credentials.json`

For capstone, the review summary should note that setup was executed through
`cmctl`, while the final runtime proof remained app-api/harness-driven.

## Testing Strategy

### CLI project

- unit/integration tests for env overrides and automation-safe defaults

### Acceptance harness

- one dedicated CLI smoke scenario
- updated capstone scenario using the CLI helper

### Full verification

- `core_matrix_cli`: full test suite
- `core_matrix`: full verification suite
- repo root: `ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh`

## Success Criteria

- acceptance can run `cmctl` without touching the real user config, keychain, or
  browser
- CLI operator smoke passes against the real local stack
- capstone setup runs through CLI evidenceably
- capstone final proof still passes unchanged after setup completes
- artifact bundle contains CLI evidence and the existing review/database proof
