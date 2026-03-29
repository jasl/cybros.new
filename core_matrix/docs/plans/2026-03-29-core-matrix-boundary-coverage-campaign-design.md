# Core Matrix Boundary Coverage Campaign Design

## Context

`core_matrix` has already completed a first audit pass across Batch 1 through
Batch 3. That work removed obvious refactor residue, strengthened several
critical-path tests, and raised trust in the existing suite. The next phase is
not another residue sweep. It is a whole-codebase campaign to ensure that the
main business branches, boundary branches, and extreme-but-realistic failure
cases are covered by tests across the product substrate.

As of the latest full `bin/rails test` run on `2026-03-29`, SimpleCov reports:

- line coverage: `50.37%` (`7528 / 14945`)

That number is not the target by itself. It is only a checkpoint. The real
goal is to make coverage correspond to meaningful branch protection.

## Goals

- Scan every application code file under `app/**/*.rb` and record its current
  testing status in a persistent working ledger.
- Strengthen tests so each important domain has coverage for:
  - primary success paths
  - validation and rejection paths
  - stale, replayed, or duplicate requests
  - extreme inputs and state-transition edge cases
- Fix implementation bugs immediately when stronger tests expose them, unless
  doing so would require major architectural redesign.
- Use facts for acceptance:
  - the working ledger covers every `app/**/*.rb` file
  - SimpleCov results are captured at campaign checkpoints

## Non-Goals

- Driving line coverage toward an arbitrary percentage target.
- Adding low-signal tests only to execute lines.
- Re-auditing already-removed residue unless a fresh scan finds more.
- Refactoring architecture without a concrete correctness reason.

## Strategy

The campaign proceeds breadth-first, then depth-first.

### Wave 1: Write-Side State Machines

Primary scope:

- `app/services/workflows/**/*`
- `app/services/turns/**/*`
- `app/services/conversations/**/*`
- `app/services/provider_execution/**/*`
- `app/services/agent_deployments/**/*`

Focus:

- state-transition legality
- malformed payloads and selector resolution
- stale replay rejection
- duplicate or idempotent execution
- cancellation, pause, retry, and resume semantics

### Wave 2: Control Plane And Recovery

Primary scope:

- `app/services/agent_control/**/*`
- `app/services/subagent_sessions/**/*`
- `app/services/installations/**/*`
- `app/services/execution_environments/**/*`
- `app/services/leases/**/*`
- `app/services/processes/**/*`

Focus:

- ownership and targeting
- lease freshness
- stale reports
- runtime drift
- recovery fallback
- nested subagent and close-in-progress behavior

### Wave 3: Read Side And External Contracts

Primary scope:

- `app/controllers/agent_api/**/*`
- `app/queries/**/*`
- `app/projections/**/*`
- `app/resolvers/**/*`
- boundary-facing publication and variable flows

Focus:

- public JSON shape
- default-path behavior
- malformed request bodies
- empty and filtered reads
- pagination and cursor rules
- `public_id` boundaries with no internal `bigint` leakage

### Wave 4: Models And Extreme Constraints

Primary scope:

- `app/models/**/*`
- `app/models/concerns/**/*`
- selected integration flows and support seams

Focus:

- illegal state combinations
- terminal-state timestamp requirements
- ownership and lineage invariants
- supported polymorphic/resource type restrictions
- append-only and supersession rules

## Working Ledger

The campaign uses two separate documents:

- findings doc:
  - stable audit conclusions
  - closed gaps
  - intentional remaining gaps
- working ledger:
  - every `app/**/*.rb` file
  - per-file status
  - scan decisions
  - actions taken
  - remaining gaps

The ledger is the factual source for acceptance that the whole codebase was
scanned.

## Status Model

Each file in the working ledger must end in one of these states:

- `done`
  - scanned and judged sufficiently covered for this campaign stage
- `needs_tests`
  - scanned and needs stronger or additional tests
- `needs_bugfix`
  - stronger tests exposed a product bug that must be fixed
- `keep_watch`
  - not immediately risky, but still worth revisiting in a later depth pass

The initial state for every file is `pending_scan`.

## Verification

Every wave follows the same loop:

1. scan files and update ledger
2. add or strengthen tests
3. fix bugs when tests prove incorrect behavior
4. run focused wave verification
5. run full `bin/rails test`
6. capture the latest SimpleCov result in the ledger and findings

## Acceptance Criteria

This campaign is complete when all of the following are true:

- the working ledger includes every `app/**/*.rb` file
- no file remains in `pending_scan`
- each wave has recorded:
  - scanned scope
  - actions taken
  - remaining gaps
- new tests cover major paths, rejection paths, and extreme branches for the
  high-risk domains
- all code changes are backed by passing focused verification and passing full
  `bin/rails test`
- the final report references the latest SimpleCov result as evidence, not as
  a vanity metric
