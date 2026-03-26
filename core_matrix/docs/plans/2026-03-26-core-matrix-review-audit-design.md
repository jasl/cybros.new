# Core Matrix Review Audit Design

## Goal

Run a broad but disciplined audit of the current `core_matrix` Ruby codebase to
find:

- leftover development code or transitional logic that should have been cleaned up
- style inconsistencies and code that works against Ruby or Rails conventions
- potential risks in boundaries, transactions, callbacks, exception handling,
  lifecycle rules, and tests

The audit scope is limited to Ruby code under `app/`, `lib/`, `config/`,
`db/`, and `test/`.

## Project Context

- `core_matrix` is a Rails application that acts as the Core Matrix product
  kernel.
- The current project emphasis is backend substrate work, with behavior notes in
  `docs/behavior/`.
- External and agent-facing boundaries must use `public_id` rather than internal
  relational `bigint` ids, per `docs/behavior/identifier-policy.md`.
- The heaviest review targets by file count are `app/services`,
  `app/models`, `app/queries`, and `test`.
- Within `app/services`, the largest namespaces are `conversations`,
  `workflows`, `agent_control`, `agent_deployments`, and `turns`.

## Review Strategy

The audit will use a risk-first layered review rather than a directory-by-
directory dump.

### Phase 1: Pre-screen

Perform a global signal scan across the scoped directories to find likely entry
points for deeper review:

- transitional naming such as `temporary`, `manual_*`, `override`, `phase*`,
  `follow_up`, `legacy`, `deprecated`, `mock`, and `dummy`
- debugging or development leftovers
- over-broad rescues
- callback-heavy models
- suspiciously long files or methods
- repeated transaction and guard templates
- possible `id` exposure at external boundaries

### Phase 2: Layered Main Pass

Review the application flow top-down:

- `controllers` for request orchestration vs business logic leakage
- `services` for orchestration quality and "bag of actions" drift
- `queries` for clean read concerns vs business decision leakage
- `models` for domain fit, callback health, and Active Record usage

This phase will prioritize the largest namespaces first because they are the
highest-yield review surface.

### Phase 3: Ruby and Rails Philosophy Pass

Evaluate whether the code follows natural Rails expression:

- responsibilities are placed in the right objects
- naming matches object roles
- common patterns are expressed idiomatically
- domain rules are neither lost in services nor overstuffed into models
- simple flows are not encoded as brittle procedural code

### Phase 4: Data and Boundary Pass

Check `config/`, `db/`, and related models and services for:

- `public_id` boundary compliance
- migration cleanup and transitional schema artifacts
- transaction and callback risks
- state and lifecycle branching
- configuration or environment splits that could hide unstable behavior

### Phase 5: Test Reverse Pass

Use tests to audit the implementation from the opposite direction:

- heavy setup indicates awkward object boundaries
- repeated scenario scaffolding indicates leaky abstractions
- missing negative-path coverage indicates risk blind spots
- assertion style exposes whether objects are easy to reason about

## Two-Pass Verification Model

Every category must be checked twice, but not by repeating the same scan.

### Pass A: Primary Review

Trace runtime paths from entry points toward lower layers and record candidate
findings for:

- leftover code
- style and philosophy drift
- risk and correctness concerns

### Pass B: Reverse Review

Re-check the same categories through different evidence:

- read tests to validate or challenge conclusions from Pass A
- scan cross-cutting rules such as `public_id`, transactions, callbacks, and
  rescue behavior
- compare sibling objects within the same namespace to detect style drift that a
  top-down read can miss

Only findings that survive both passes should be reported as high-confidence
issues. Weaker signals stay in a watch list.

## Finding Taxonomy

### Must Fix

Use for:

- genuine leftover or transitional code
- real boundary or lifecycle risks
- strong Rails or Ruby violations with concrete maintenance or correctness cost

### Suggested Improvements

Use for:

- style inconsistency
- unstable abstractions
- repetitive or awkward code that is not an immediate defect

### Watch List

Use for:

- patterns that are not yet clearly wrong but are drifting in a risky direction
- testing holes that prevent confident judgment
- namespaces showing early signs of becoming dumping grounds

## Output Format

The final audit output must include:

1. Findings, ordered by severity
2. Suggestions, for non-blocking but valuable cleanup
3. Watch list items, for follow-up attention
4. A cross-check summary showing what the second pass confirmed, weakened, or
   expanded

Each finding must include:

- category
- why it matters
- evidence path and key lines
- reasoning basis
- recommended action

## Acceptance Criteria

The audit is only complete when all of the following are true:

- all scoped Ruby directories have been covered
- each issue category has been checked through both the primary and reverse pass
- every reported conclusion has evidence and file references
- conclusions are written to disk in a dedicated findings artifact
- the report distinguishes must-fix items from suggestions and watch-list items
- the output is specific enough to act on without re-reading the codebase first

## Task Relationship Model

The work is sequential with explicit dependencies:

1. Pre-screening produces the high-yield review targets
2. The layered main pass validates those targets in context
3. The data and boundary pass checks cross-cutting correctness rules
4. The test reverse pass re-checks the earlier judgments
5. The findings report and completeness check close the audit

This dependency chain is intentionally linear so the audit can run
deterministically and fully automatically without relying on ad hoc branching.

## Automation Readiness

The review is designed to be executable end-to-end by an agent without manual
intervention because:

- the scope is explicit
- the phase order is fixed
- each pass has defined evidence sources
- the output structure is predetermined
- completion is gated by written artifacts and acceptance checks

## Documentation Integrity Check

The design and plan documents were reviewed for completeness on `2026-03-26`.

- the task goal is explicit in this design and in the execution-plan header
- the work scope is explicit and limited to Ruby code in the agreed directories
- the review conclusions are required to land in a dedicated findings artifact
- the acceptance and completion gates are explicit rather than implied
- the task relationships are linear and dependency-safe
- the work can be executed automatically without inventing extra review rules at
  runtime
