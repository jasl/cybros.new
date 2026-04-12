# 2048 Capstone Acceptance Restoration Design

## Goal

Restore the `2048` capstone as a first-class acceptance proof for the current
`CoreMatrix + Fenix + Nexus` architecture without turning it back into a daily
gate. The capstone must remain the strongest end-to-end proof that a real
provider-backed agent loop can complete meaningful work through the full stack.

## Product Positioning

The acceptance suite now has two layers:

- **Active suite**: routine scenario coverage and load wrappers that should run
  during regular development.
- **Capstone proof**: a heavy, expensive, real-provider scenario that serves as
  the final system-level proof before close-out work.

The `2048` capstone belongs to the second layer. It should be easy to discover
and easy to invoke, but it should not silently inflate the normal acceptance
gate.

## Constraints

- The capstone must use a **real provider-backed agent loop**.
- The capstone must exercise the **real browser/API path**.
- The capstone must target the **current split runtime topology** rather than
  the retired bundled or Dockerized-Fenix-only model.
- The capstone must remain a **formal acceptance entrypoint**, not an archived
  script or an undocumented one-off.
- The capstone must support **active-suite discovery** while remaining
  **disabled by default**.

## Recommended Architecture

### 1. Restore the capstone as a formal acceptance scenario and wrapper

Reintroduce:

- `acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
- `acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh`

The shell wrapper remains the preferred human/operator entrypoint for the final
proof. The scenario remains the canonical implementation.

### 2. Rebuild the capstone against the current split topology

The previous capstone was archived because it modeled a Dockerized Fenix runtime
instead of the current `Fenix + Nexus` split. The restored scenario must:

- bootstrap against current `Acceptance::ManualSupport`
- register the current agent/runtime shape
- launch the real runtime worker path supported by the current stack
- preserve current artifact expectations only where they still serve a clear
  contract purpose

We should not reintroduce obsolete program semantics just to make the historical
scenario compile.

### 3. Extend `Acceptance::ActiveSuite` with optional entrypoints

`Acceptance::ActiveSuite` should expose:

- always-on entrypoints
- optional entrypoints

The `2048` capstone becomes an optional entrypoint controlled by an explicit
environment variable. The runner should:

- include optional entrypoints only when enabled
- print a visible skip message when an optional entrypoint is not enabled

This avoids the current problem where a formal proof can disappear from the live
suite surface entirely.

### 4. Keep the capstone as a hard real-provider contract

There should be no stubbed or local-only version of the capstone. The capstone
is not a smoke test; it is the strongest proof that the real system can drive a
non-trivial task to completion.

If the required provider/browser/runtime prerequisites are absent, the capstone
may be skipped by default because it is not enabled, but once explicitly
enabled, failure must be real failure.

## Suite Audit Criteria

While restoring the capstone, the active acceptance suite should be audited
against these rules:

1. Every active scenario must have a clear purpose statement.
2. Every active scenario must validate a distinct contract or a distinct
   extreme/edge condition.
3. Heavy scenarios should remain heavy only when they prove something lighter
   scenarios cannot.
4. Obsolete topology assumptions should be removed rather than tolerated behind
   compatibility language.
5. Archived scenarios should stay archived unless they are restored as current
   proofs.

## Current Scenario Taxonomy

The current active suite already clusters into useful groups:

- Bring-your-own pairing:
  - `bring_your_own_agent_validation`
  - `bring_your_own_execution_runtime_validation`
- Runtime/tool governance and steering:
  - `during_generation_steering_validation`
  - `governed_mcp_validation`
  - `governed_tool_validation`
- Human supervision and orchestration:
  - `human_interaction_wait_resume_validation`
  - `subagent_wait_all_validation`
- Provider-backed smoke:
  - `provider_backed_turn_validation`
- Skills and mixed behavior:
  - `fenix_skills_validation`
- Multi-node pressure wrappers:
  - load smoke / target / stress wrappers

The restored `2048` capstone should sit above these as the only heavy,
multi-artifact, final proof scenario.

## Contract Changes

### `Acceptance::ActiveSuite`

Introduce a stable API like:

- `entrypoints`
- `optional_entrypoints`
- `enabled_optional_entrypoints`
- `skipped_optional_entrypoints`

This keeps runner behavior explicit and testable.

### `run_active_suite.sh`

The runner should:

- run all default entrypoints
- run enabled optional entrypoints
- print skip messages for disabled optional entrypoints
- still fail if any selected entrypoint fails

### Capstone Enablement

Use one explicit environment variable for the optional capstone gate. Keep the
name specific and discoverable, for example:

- `ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1`

The dedicated shell script must not require this variable; it is the direct
entrypoint and should always run the capstone when invoked.

## Testing Strategy

### Contract tests

- `Acceptance::ActiveSuiteContractTest` should verify optional entrypoints and
  skip semantics.
- A restored `FenixCapstoneAcceptanceContractTest` should verify that:
  - the shell wrapper exists
  - the scenario exists
  - the active suite exposes the capstone as optional
  - the capstone enable flag is documented in code and runner behavior

### Scenario integrity

The restored capstone scenario should keep only the artifact and quality gates
that still reflect current product behavior. Historical assertions that only
exist to support retired topology assumptions should be dropped.

## Trade-offs

### Why not restore the old capstone verbatim?

Because it would reintroduce obsolete architecture assumptions and mislead the
acceptance suite about the current stack.

### Why not make the capstone a normal active-suite gate?

Because the scenario is intentionally expensive and operationally heavy. It is
best treated as a final system proof, not a routine daily gate.

### Why not keep it only as a script?

Because scripts that are not represented in the active acceptance manifest are
easy to forget, silently remove, or let drift.

## Success Criteria

This work is complete when:

1. The `2048` capstone is restored as a current acceptance scenario and shell
   wrapper.
2. The capstone targets the current split runtime architecture.
3. `Acceptance::ActiveSuite` knows about the capstone as an optional entrypoint.
4. The normal active suite skips it by default with an explicit reason.
5. Enabling the capstone through the suite runs the real provider-backed proof.
6. The acceptance suite is re-audited so active scenarios remain orthogonal and
   purposeful.
