# Verification And Manual Validation Baseline

## Scope

This note captures the backend verification baseline for the phase 1 substrate
and the retained Phase 2 acceptance operator path.

## Current Behavior

- Manual backend validation is expected to be reproducible from shell commands,
  Rails runner scripts, HTTP requests, and
  `script/manual/dummy_agent_runtime.rb`, not browser UI flows.
- Development-state resets must use
  `ApplicationRecord.with_connection { |conn| conn.disable_referential_integrity { ... } }`
  and delete the current dependency order from the checklist. Older ad-hoc
  `delete_all` chains became stale once more foreign-key roots were added.
- `script/manual/dummy_agent_runtime.rb register` is part of the supported
  registry validation path and must send the enrollment token plus a stable
  `environment_fingerprint`. The manual checklist currently drives that through
  `CORE_MATRIX_ENVIRONMENT_FINGERPRINT`.
- Publication validation in phase 1 is intentionally service-level.
  `Publications::PublishLive`, `Publications::RecordAccess`,
  `Publications::LiveProjection`, and `Publications::Revoke` are the
  authoritative publication surfaces until public HTTP routes exist.
- Blocking approval requests pause the existing workflow run by moving it to
  `wait_state = "waiting"` with a `HumanInteractionRequest` blocking resource,
  and approval resolution returns the same workflow run to `wait_state = "ready"`
  while preserving append-only conversation events.
- `bin/rails db:seed` is part of the supported development setup path:
  - in `development` and `test`, it should leave the shipped mock path usable
    through `role:mock` or explicit `candidate:dev/...` selection even when no
    real-provider credential is configured
  - when `OPENAI_API_KEY` or `OPENROUTER_API_KEY` is present, it should leave
    the corresponding real provider immediately usable without changing
    conversation selector mode away from `auto`
- Selector validation in the manual checklist must cover all of:
  - conversation `auto`
  - availability filtering from missing credentials or environment gating
  - role-local filtering from a disabled model
  - role-local fallback after reservation denial
  - explicit candidate hard failure, including a disabled model
  - specialized-role exhaustion hard failure
  - one-time manual resume override
  - drift-triggered manual retry
- Phase 2 acceptance now additionally relies on concrete operator scripts under
  `script/manual/phase2_*`, run with `bundle exec ruby`, to cover:
  - bundled `Fenix` fast terminal
  - real provider-backed bundled turn using `.env`-materialized
    `OPENROUTER_API_KEY`
  - during-generation steering, feature-disabled rejection, and stale-work
    fencing
  - human-interaction wait/resume
  - subagent `wait_all`
  - `process_run` close handling
  - governed tool invocation
  - governed Streamable HTTP MCP invocation
  - bundled deployment rotation upgrade and downgrade
  - independent external `Fenix`
  - built-in system skill and third-party skill activation flows
  - workflow proof export
- The checklist at
  `../checklists/2026-03-24-core-matrix-kernel-manual-validation.md` is the
  authoritative Phase 2 operator script, and
  `../../docs/reports/phase-2/` is the committed proof-artifact ledger.

## Validation Notes

- The `2026-03-25` rerun exercised live registration, heartbeat, health,
  transcript pagination, canonical variable APIs, and machine-side
  human-interaction creation against `bin/dev`.
- The same rerun exercised installation bootstrap, invitation consumption,
  admin role changes, user binding, bundled runtime reconciliation, provider
  seed baseline, credential lifecycle, selector resolution, conversation
  structure and rewrite flows, human forms and tasks, open-request projection,
  and publication access logging through Rails runner scripts.
- The `2026-03-30` Phase 2 acceptance run exercised real bundled/external
  `Fenix`, real provider-backed OpenRouter execution, wait/resume and
  subagent orchestration, governed tool/MCP paths, deployment rotation,
  skill activation, and proof export, with proof packages stored under
  `../../docs/reports/phase-2/`.
