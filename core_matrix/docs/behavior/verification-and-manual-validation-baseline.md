# Verification And Manual Validation Baseline

## Scope

This note captures the backend verification baseline that closed phase 1
substrate work.

## Current Behavior

- Manual backend validation is expected to be reproducible from shell commands,
  Rails runner scripts, HTTP requests, and
  `script/manual/dummy_agent_runtime.rb`, not browser UI flows.
- Development-state resets must use
  `ApplicationRecord.with_connection { |conn| conn.disable_referential_integrity { ... } }`
  and delete the current dependency order from the checklist. Older ad-hoc
  `delete_all` chains became stale once more foreign-key roots were added.
- `script/manual/dummy_agent_runtime.rb register` is part of the supported
  registry validation path and must send both the enrollment token and the
  execution environment id. The required environment variable is
  `CORE_MATRIX_EXECUTION_ENVIRONMENT_ID`.
- Publication validation in phase 1 is intentionally service-level.
  `Publications::PublishLive`, `Publications::RecordAccess`,
  `Publications::LiveProjectionQuery`, and `Publications::Revoke` are the
  authoritative publication surfaces until public HTTP routes exist.
- Blocking approval requests pause the existing workflow run by moving it to
  `wait_state = "waiting"` with a `HumanInteractionRequest` blocking resource,
  and approval resolution returns the same workflow run to `wait_state = "ready"`
  while preserving append-only conversation events.
- Selector validation in the manual checklist must cover all of:
  conversation `auto`, role-local fallback after reservation denial, explicit
  candidate hard failure, specialized-role exhaustion hard failure, one-time
  manual resume override, and drift-triggered manual retry.

## Validation Notes

- The `2026-03-25` rerun exercised live registration, heartbeat, health,
  transcript pagination, canonical variable APIs, and machine-side
  human-interaction creation against `bin/dev`.
- The same rerun exercised installation bootstrap, invitation consumption,
  admin role changes, user binding, bundled runtime reconciliation, credential
  lifecycle, recovery, selector resolution, conversation structure and rewrite
  flows, human forms and tasks, open-request projection, and publication access
  logging through Rails runner scripts.
