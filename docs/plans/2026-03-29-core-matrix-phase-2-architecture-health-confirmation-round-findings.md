# Core Matrix Phase 2 Architecture Health Confirmation Round Findings

## Scope

- This is a post-archive confirmation round.
- The archived iterative audit is the baseline.
- The purpose is to confirm whether any additional high-confidence structural issues remain undiscovered.
- The review still includes the `core_matrix <-> agents/fenix` boundary.

## Archived Baseline

The archived iterative audit judged the current `core_matrix` to be governable
but still most exposed at the newer delegation and runtime-contract seams.
Provider request-setting ownership, blocker-summary projection, and
machine-facing capability formatting looked materially improved, while recovery,
runtime capability preservation, subagent close control, and the
`core_matrix <-> agents/fenix` boundary remained the structural pressure points.

- Archived confirmed findings:
  deployment recovery still has duplicate rebinding authority; capability
  preservation checks are narrower than the runtime contract they claim to
  protect; `SubagentSession` close progression is split across two state
  machines; the `core_matrix <-> fenix` execution-context contract drops real
  model hints on the floor.
- Archived risk smells most likely to hide adjacent undiscovered work:
  capability-snapshot reuse rules are duplicated across registration paths;
  Fenix treats `allowed_tool_names` as trace data instead of an execution-time
  constraint; mutable-state and quiescence enforcement still ask callers to know
  too many wrapper families.
- Archived top structural priorities:
  unify runtime capability preservation and reuse rules; collapse
  `SubagentSession` close progression onto one canonical state model; repair the
  `core_matrix <-> fenix` execution-context contract and lock it down with
  cross-project contract tests.

## Confirmation Passes

- [ ] Runtime capability preservation and reuse rules
- [ ] `SubagentSession` close progression and neighboring close-control readers
- [ ] `core_matrix <-> fenix` execution-context contract, including model hints
  and visible-tool semantics
- [ ] Wrapper and payload drift around the archived hotspots

## New High-Confidence Findings

## No-New-Finding Judgment

## Completeness Check
