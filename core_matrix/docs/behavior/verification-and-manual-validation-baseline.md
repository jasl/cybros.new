# Verification And Manual Validation Baseline

## Scope

This note captures the current verification baseline for the retained
acceptance operator path.

## Current Behavior

- Manual backend validation is expected to be reproducible from shell commands,
  Rails runner scripts, HTTP requests, and
  `script/manual/dummy_agent_runtime.rb`, not browser UI flows.
- Development-state resets now rebuild the database through
  `bin/rails db:reset` before reapplying the acceptance seed baseline. This
  replaced the older in-process `delete_all` chains once foreign-key roots
  started changing too frequently to keep a static reset list reliable.
- `script/manual/dummy_agent_runtime.rb register` is part of the supported
  registry validation path and must send the enrollment token plus a stable
  `execution_runtime_fingerprint`. The manual checklist currently drives that through
  `CORE_MATRIX_RUNTIME_FINGERPRINT`.
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
- The current agent-loop acceptance baseline now additionally relies on the
  reusable harness in `../acceptance/lib/manual_support.rb` plus
  concrete operator scripts under `../../acceptance/scenarios/*`, run through
  `bin/rails runner ../../acceptance/scenarios/...`, to cover:
  - during-generation steering
  - independent external `Fenix`
  - built-in system skill and third-party skill activation flows
  - governed tool invocation
  - governed Streamable HTTP MCP invocation
  - human-interaction wait/resume
  - provider-backed turn execution
  - subagent `wait_all`
  - Shared-Fenix / Multi-Nexus smoke, target, and stress load profiles
- Historical backend operator baselines now live under `../../docs/archived/`.
  The current product acceptance harness lives under `../../acceptance/`.
  Generated run logs and artifacts now live under `../../acceptance/logs/` and
  `../../acceptance/artifacts/`.

## Validation Notes

- The `2026-03-25` rerun exercised live registration, heartbeat, health,
  transcript pagination, canonical variable APIs, and machine-side
  human-interaction creation against `bin/dev`.
- The same rerun exercised installation bootstrap, invitation consumption,
  admin role changes, user binding, bundled runtime reconciliation, provider
  seed baseline, credential lifecycle, selector resolution, conversation
  structure and rewrite flows, human forms and tasks, open-request projection,
  and publication access logging through Rails runner scripts.
- Current acceptance runs exercise external `Fenix`, provider-backed or mock
  execution through `Nexus`, wait/resume and subagent orchestration, governed
  tool and MCP paths, skill activation, and shared-agent / multi-runtime load
  profiles. Generated evidence stays under `../../acceptance/artifacts/`
  instead of being committed.
