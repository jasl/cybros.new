# Core Matrix Test Suite Audit And Improvement Design

## Context

`core_matrix` is still in the backend substrate phase. The current product
surface is the execution graph, conversation lifecycle, provider execution, and
runtime control plane rather than browser-facing app flows.

After fixing SimpleCov's parallel worker merging, the latest full `rake test`
coverage report is:

- line coverage: `50.34%` (`7524 / 14945`)

That number is now trustworthy enough to guide prioritization, but it should
not become the primary optimization target. The current need is to verify that
the test suite actually protects correctness, remove low-signal tests, and
raise meaningful coverage around the core substrate.

## Goals

- Verify that existing tests protect business and system invariants rather than
  merely reproducing implementation details.
- Identify and remove tests that are low-signal, redundant, or only "pass by
  assembly" through heavy setup without strong assertions.
- Improve coverage in critical backend paths by adding tests for real missing
  behaviors, especially failure paths, state transitions, and boundary rules.
- Leave the suite easier to maintain by making test intent explicit per domain.

## Non-Goals

- Chasing coverage in low-value areas just to move the percentage.
- Prioritizing browser-facing controller, view, channel, or mailer coverage
  while the product is still backend-first.
- Refactoring product code unless a test rewrite exposes an actual correctness
  bug or an untestable design seam.
- Treating all uncovered lines as equally important.

## Observations

- The test suite is concentrated where the product currently lives:
  `test/services`, `test/integration`, `test/models`, and `test/requests`.
- The app code is similarly concentrated in `app/services`, `app/models`, and
  `app/queries`.
- There are already strong examples of high-value tests that encode invariants,
  such as workflow cycle rejection and branch-context attachment filtering.
- Coverage hotspots in important service code remain, including:
  - `app/services/workflows/build_execution_snapshot.rb`
  - `app/services/provider_execution/persist_turn_step_success.rb`
  - `app/services/turns/start_user_turn.rb`
  - `app/services/lineage_stores/compact_snapshot.rb`
  - `app/services/subagent_connections/spawn.rb`

## Quality Rubric

Each test file should be classified into one of three buckets.

### 1. Keep And Strengthen

Use this when the test already protects a meaningful invariant, but still needs
harder assertions or missing negative cases.

Signals:

- verifies append-only or lineage invariants
- verifies state transition semantics
- verifies failure modes, not only success paths
- verifies agent-facing or integration-facing contracts

### 2. Rewrite Or Lower

Use this when the test targets the right area but at the wrong layer or with
too-indirect assertions.

Signals:

- mainly proves a record was created but not why it is correct
- asserts internal helpers or transient payload shape rather than stable
  behavior
- duplicates stronger coverage that already exists in a neighboring
  integration/service test

### 3. Delete

Use this when the test adds little or no protection.

Signals:

- only repeats framework defaults without product-specific rules
- relies on large setup with weak assertions that do not encode an invariant
- duplicates the same behavior at a noisier layer without adding contract
  coverage

## Scope And Order

The work should proceed in three batches.

### Batch 1: Execution Critical Path

Priority directories:

- `app/services/workflows`
- `app/services/turns`
- `app/services/conversations`
- `app/services/provider_execution`
- `app/services/lineage_stores`

Reason:

This batch defines turn creation, workflow construction, context assembly,
execution persistence, failure handling, branching, and retained state. These
are the current product core.

Expected outcomes:

- stronger invariants in service and integration tests
- missing failure-path coverage added
- low-signal tests in the same domains removed or rewritten

### Batch 2: Runtime Control Plane

Priority directories:

- `app/services/agent_control`
- `app/services/agent_deployments`
- `app/services/subagent_connections`
- `app/services/installations`
- `app/services/execution_environments`

Reason:

These paths control registration, routing, recovery, resumption, and runtime
ownership. Failures here are often subtle and under-protected by shallow happy
path tests.

### Batch 3: Read Side And API Boundary

Priority directories:

- `app/queries`
- `app/projections`
- `app/resolvers`
- `app/controllers/agent_api`
- `test/requests`

Reason:

These are important but mostly project persisted state and contracts that sit on
top of the write-side substrate. They should be calibrated after the write side
is hardened.

## Execution Strategy

Use an audit-and-repair loop rather than a full-repo review followed by one
large patch.

For each selected domain:

1. Inspect the service/query code and its current tests.
2. Classify each test file as keep/strengthen, rewrite/lower, or delete.
3. Identify missing high-value scenarios:
   - failure paths
   - state transitions
   - idempotency
   - lock and concurrency semantics
   - public or agent-facing boundaries
4. Apply a small batch of edits:
   - delete low-value tests
   - tighten weak assertions
   - add missing high-value tests
5. Run focused verification immediately for the touched files.
6. Re-check coverage only after the batch is behaviorally stronger.

## Deliverables

The audit should produce three concrete outputs:

1. A domain-by-domain findings ledger describing which tests are strong, weak,
   or removable.
2. A first remediation batch for Batch 1 with real test edits.
3. A post-batch coverage readout interpreted in context, not treated as a score
   by itself.

## Acceptance Criteria

This effort is successful when:

- Batch 1 has an explicit audit result for each critical directory.
- Removed tests can be justified as redundant or low-signal.
- Strengthened or new tests clearly encode invariants, failure modes, or
  contract boundaries.
- The suite is more trustworthy for core substrate correctness, even if the raw
  coverage number changes only modestly.
- Coverage increases come from meaningful branch and behavior protection rather
  than cosmetic line execution.
