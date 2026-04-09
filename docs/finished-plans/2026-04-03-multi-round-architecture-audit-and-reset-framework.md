# Multi-Round Architecture Audit And Reset Framework

## Status

- Date: 2026-04-03
- Status: approved baseline for the next reset cycle

## Goal

Define one reusable framework for auditing and resetting the `Core Matrix` and
`Fenix` codebase across multiple destructive rounds without re-negotiating the
overall method after each round.

## Fixed Product Principles

These rules are fixed for every round:

- all user-visible agent-loop progression remains owned by `Core Matrix`
- `Core Matrix` `Workflow` remains the only orchestration truth
- `Fenix` may own program behavior and execution-runtime behavior, but it does
  not become the workflow scheduler
- every completed round must still pass the same acceptance standard,
  especially the provider-backed `2048` capstone checklist
- destructive schema and protocol changes are allowed when they improve
  correctness, modularity, and long-term maintainability

## Why This Work Uses Multiple Rounds

The product already works end to end, but major structural improvements will
still expose new bugs, hidden coupling, stale abstractions, and verification
gaps. Multi-round reset is therefore deliberate:

- early rounds prioritize high-value structural change
- later rounds clean up the issues exposed by earlier simplification
- low-value style work stays out unless attached to a structural fix
- every round must converge back to a fully accepted product baseline

## Round Sequence

### Round 1

Primary sweep order:

1. code layering, module boundaries, and responsibility placement
2. schema, aggregates, and source-of-truth cleanup
3. `Core Matrix <-> Fenix` protocol, communication, and hot-path data flow

### Round 2

Validation sweep order:

1. protocol and communication hardening
2. schema and aggregate follow-up cleanup
3. codebase simplification, dead-code removal, and layering re-check

### Round 3

Optional final convergence round:

- only if rounds 1 and 2 expose additional meaningful structural debt
- restricted to lower-value tail items that still affect maintainability or
  acceptance stability

## Audit Buckets

Every round classifies findings into these buckets:

1. `Core Matrix` layering and module boundaries
2. `Fenix` layering and module boundaries
3. cross-project responsibility placement
4. schema and aggregate boundaries
5. data flow and write amplification
6. protocol and payload redundancy
7. hot-path performance
8. dead code and duplicate implementations
9. verification quality and documentation entrypoints

## Priority Rules

### `P0`

- breaks a fixed product principle
- creates conflicting sources of truth
- leaves workflow ownership or orchestration boundaries incorrect

### `P1`

- creates ongoing maintenance cost, bug risk, schema lock-in, or material
  performance waste
- includes schema naming, structure, and aggregate-boundary problems because
  those become expensive to change once a system is live

### `P2`

- worthwhile local cleanup only when attached to higher-value changes
- not a driver for standalone reset work

Code style alone is not a round driver. Schema structure and naming can be.

## Required Outputs Per Round

Each round must produce:

1. an audit report
   - high-risk areas
   - `P0/P1/P2` findings
   - concrete evidence paths
2. a reset candidate list
   - `must do`
   - `should do`
   - `optional`
   - `not now`
3. a round-specific implementation plan
   - exact files
   - exact verification commands
   - explicit deletion targets
4. a post-round review note
   - what improved
   - what new issues surfaced
   - what should roll into the next round

## Required Completion Gate Per Round

No round is complete until all of the following are true with fresh evidence:

- `core_matrix` verification commands from `AGENTS.md` pass
- `agents/fenix` verification commands from `AGENTS.md` pass
- `core_matrix/vendor/simple_inference` verification passes when touched
- repo-wide scans for dead names and deleted concepts are clean for active
  implementation surfaces
- the provider-backed `2048` capstone acceptance passes under the current
  product contract

## Fresh Start Gate

Because compatibility is intentionally out of scope during this reset cycle,
every round starts from fresh processes and a fresh runtime surface:

- before each round begins, stop already running host services and relevant
  containers, then restart them from the current source tree
- after any contract change, repeat that fresh start before trusting new
  verification or acceptance evidence
- do not rely on long-lived host Rails servers, old runtime manifests, or
  previously started container workers when judging current behavior
- external harness steps and round checklists should encode this rule directly
  instead of depending on operator memory
- in Docker mode, rebuild the `Fenix` image from the current source tree before
  starting containers; do not patch repo files into an already-running
  container
- the default external harness entrypoints are:
  - `/Users/jasl/Workspaces/Ruby/cybros/acceptance/bin/fresh_start_stack.sh`
  - `/Users/jasl/Workspaces/Ruby/cybros/acceptance/bin/run_with_fresh_start.sh`
- when a target acceptance script expects a non-default runtime port, pass the
  matching `FENIX_RUNTIME_BASE_URL` into the wrapper so the fresh-start step
  boots the correct runtime endpoint before running the script

## Documentation Rules

- active round planning lives in `docs/plans/`
- completed round plans and accepted designs move to
  `docs/finished-plans/`
- archived `Fenix` planning records live in `docs/finished-plans/fenix/`
- current entrypoint documents should point to active work only
- historical records may stay historical, but they must not pretend to be the
  current source of truth

## Decision Rules For Candidate Changes

Prefer a change when it:

- removes a wrong boundary instead of wrapping it
- deletes duplicated state, payload, or orchestration logic
- simplifies the `Core Matrix <-> Fenix` contract
- reduces write amplification or repeated transformation work
- makes the acceptance path shorter or more reliable
- produces a codebase that is easier to explain in terms of module ownership

Defer a change when it:

- is mostly stylistic
- adds abstraction without deleting complexity
- optimizes a path without evidence that the path matters
- broadens product scope instead of tightening the current design

## Starting A New Round

When a new round begins:

1. write a round-specific audit/design document in `docs/plans/`
2. write the matching implementation plan in `docs/plans/`
3. perform the fresh-start gate for host services and relevant containers
4. execute the round in bounded batches
5. rerun full verification and acceptance
6. archive the completed round documents to `docs/finished-plans/`

This framework stays active until the codebase is judged structurally ready for
the next product phase.
