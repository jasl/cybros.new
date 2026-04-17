# Monorepo Verification Rebuild Design

## Goal

Replace the current mixed `acceptance` layout with a first-class monorepo
`verification` project that is easy to explain, owns its own harness/tests, and
does not leak implementation back into product projects.

The concrete target is:

- create a dedicated top-level `verification/` project
- remove the live `acceptance/` directory and terminology from the active
  developer surface
- move repo-root verification assets and `core_matrix` verification helpers into
  `verification/`
- keep `core_matrix`, `core_matrix_cli`, `agents/fenix`, and `images/nexus` in
  their current top-level positions
- allow destructive cleanup with no compatibility layer

## Problem

The current verification surface is hard to understand because ownership is
split across multiple places:

- top-level `acceptance/` contains the main harness, scenarios, perf helpers,
  proof artifacts, and runner scripts
- repo-root `Rakefile` and `test/acceptance/*` still behave like harness-owned
  verification assets
- `core_matrix/lib/manual_acceptance/*` still owns harness logic that should not
  live inside product code
- `core_matrix/test/lib/acceptance/*` and
  `core_matrix/test/lib/manual_acceptance/*` test harness/scenario behavior from
  inside the product test tree
- `core_matrix/test/e2e/protocol/*` already uses `e2e` terminology for genuine
  product-owned end-to-end tests, so the current vocabulary is inconsistent

This creates three distinct failures:

1. **Unclear ownership**
   - readers cannot tell whether a file belongs to product code or monorepo
     verification infrastructure
2. **Terminology drift**
   - `acceptance`, `manual_acceptance`, `e2e`, `capstone`, `active suite`, and
     `perf` are used as overlapping concepts instead of a clean hierarchy
3. **Poor open-source readability**
   - a newcomer cannot infer what to run, what each suite proves, or where to
     place new verification work

## Recommendation

Rebuild the verification surface as a dedicated monorepo subproject named
`verification/`.

Use the following vocabulary:

- `verification`
  - the monorepo-owned validation project
- `e2e`
  - automated black-box or black-box-like multi-project scenarios
- `perf`
  - load, topology, and gate-oriented performance validation
- `proof`
  - final proof / capstone lanes and proof-artifact generation
- `support`
  - harness-only helpers
- `adapters`
  - explicit path/command/env bridges into product projects

Do **not** keep `acceptance/` as a long-lived alias. This is an internal
developer workflow surface. A direct cut is preferable to a gradual migration.

## Scope

### In Scope

- create `verification/` as a dedicated top-level verification project with its own harness bundle and explicit CoreMatrix-hosted lanes
- move the live `acceptance/` harness into `verification/`
- move repo-root `Rakefile` and repo-root `test/acceptance/*` into
  `verification/`
- move harness-owned verification helpers and tests out of `core_matrix`
- define explicit adapters for `core_matrix`, `core_matrix_cli`, `agents/fenix`,
  and `images/nexus`
- remove obsolete verification code, tests, docs, and developer flows that only
  exist to support the old layout
- update CI, AGENTS guidance, and live docs to point only at `verification/`
- update repo ignore rules so generated verification artifacts remain untracked

### Out Of Scope

- moving top-level product project directories
- changing product behavior for `core_matrix`, `core_matrix_cli`,
  `agents/fenix`, or `images/nexus` beyond what is needed for verification path
  updates
- preserving a compatibility surface for old `acceptance/...` paths
- mass-rewriting archived documents for historical consistency

## Target Structure

```text
verification/
  README.md
  Gemfile
  Rakefile
  bin/
    run_active_suite.sh
    run_with_fresh_start.sh
    fresh_start_stack.sh
    run_multi_fenix_core_matrix_load.sh
    multi_fenix_core_matrix_load_smoke.sh
    multi_fenix_core_matrix_load_target.sh
    multi_fenix_core_matrix_load_stress.sh
    fenix_capstone_app_api_roundtrip_validation.sh
  lib/
    verification/
      boot.rb
      active_suite.rb
      adapters/
        core_matrix.rb
        core_matrix_cli.rb
        fenix.rb
        nexus.rb
      support/
        cli_support.rb
        governed_validation_support.rb
        host_validation.rb
      suites/
        e2e/
          conversation_runtime_validation.rb
          manual_support.rb
          runtime_registration.rb
        perf/
          benchmark_reporting.rb
          event_reader.rb
          gate_evaluator.rb
          metrics_aggregator.rb
          profile.rb
          provider_catalog_override.rb
          report_builder.rb
          runtime_registration_matrix.rb
          runtime_slot.rb
          topology.rb
          workload_driver.rb
          workload_executor.rb
          workload_manifest.rb
        proof/
          capstone_app_api_roundtrip.rb
          capstone_review_artifacts.rb
  scenarios/
    e2e/
    perf/
    proof/
  test/
    adapters/
    contracts/
    scenarios/
    suites/
      e2e/
      perf/
      proof/
    support/
  artifacts/
  logs/
```

## Ownership Model

### `verification/` Owns

- monorepo-wide harness orchestration
- active suite and final proof manifests
- scenario entrypoints and wrapper scripts
- artifact and review bundle generation
- CLI automation support for `core_matrix_cli`
- perf topology, metrics, and gate evaluation
- helper code that exists only to support verification
- tests that primarily assert verification harness behavior

### Product Projects Own

- unit, integration, and product-local system tests
- product-local e2e tests that prove the product itself rather than the
  monorepo harness
- public command surfaces and runtime behavior that verification calls into

### Adapter Rule

`verification/` may reach into fixed monorepo project locations, but only
through explicit adapter code. Adapters own:

- path discovery
- command construction
- environment setup
- clear failure messages when a target project is missing or misconfigured

Adapters do **not** own business assertions or scenario semantics.

## Test Placement Rules

### Keep In `core_matrix`

Keep tests that prove CoreMatrix product behavior, such as:

- [core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb)
- [core_matrix/test/e2e/protocol/mailbox_delivery_e2e_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/mailbox_delivery_e2e_test.rb)
- [core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb)
- [core_matrix/test/e2e/protocol/retry_semantics_e2e_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/retry_semantics_e2e_test.rb)
- [core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb)

These tests should remain product-owned because they validate CoreMatrix
protocol, lifecycle, and persistence behavior.

### Move To `verification`

Move tests whose primary subject is harness/scenario/proof behavior, such as:

- [core_matrix/test/lib/acceptance/active_suite_contract_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/active_suite_contract_test.rb)
- [core_matrix/test/lib/acceptance/benchmark_reporting_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/benchmark_reporting_test.rb)
- [core_matrix/test/lib/acceptance/capstone_review_artifacts_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/capstone_review_artifacts_test.rb)
- [core_matrix/test/lib/acceptance/cli_support_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/cli_support_test.rb)
- [core_matrix/test/lib/acceptance/core_matrix_cli_operator_smoke_contract_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/core_matrix_cli_operator_smoke_contract_test.rb)
- [core_matrix/test/lib/acceptance/host_validation_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/host_validation_test.rb)
- [core_matrix/test/lib/acceptance/manual_support_contract_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/manual_support_contract_test.rb)
- [core_matrix/test/lib/acceptance/manual_support_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/manual_support_test.rb)
- [core_matrix/test/lib/acceptance/perf_provider_catalog_override_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/perf_provider_catalog_override_test.rb)
- [core_matrix/test/lib/acceptance/perf_workload_contract_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/perf_workload_contract_test.rb)
- [core_matrix/test/lib/acceptance/perf_workload_executor_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/perf_workload_executor_test.rb)
- [core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb)
- [core_matrix/test/lib/fresh_start_stack_contract_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/fresh_start_stack_contract_test.rb)
- [core_matrix/test/lib/acceptance/specialist_subagent_export_contract_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/specialist_subagent_export_contract_test.rb)
- [core_matrix/test/lib/acceptance/workspace_agent_model_override_contract_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/workspace_agent_model_override_contract_test.rb)
- [core_matrix/test/lib/manual_acceptance/conversation_runtime_validation_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/manual_acceptance/conversation_runtime_validation_test.rb)
- [test/acceptance/capstone_review_artifacts_test.rb](/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/capstone_review_artifacts_test.rb)
- [test/acceptance/perf/gate_evaluator_test.rb](/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/gate_evaluator_test.rb)
- [test/acceptance/perf/metrics_aggregator_test.rb](/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/metrics_aggregator_test.rb)
- [test/acceptance/perf/profile_test.rb](/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/profile_test.rb)
- [test/acceptance/perf/runtime_slot_test.rb](/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/runtime_slot_test.rb)
- [test/acceptance/perf/topology_test.rb](/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/topology_test.rb)
- [test/acceptance/perf/workload_driver_test.rb](/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/workload_driver_test.rb)
- [test/acceptance/perf/workload_manifest_test.rb](/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/workload_manifest_test.rb)

These tests belong with the code they validate.

### Optional Thin Product Contracts

If a product project needs a guard against breaking a stable verification-facing
surface, keep only a small number of narrow contract tests under a clearly
named path such as `test/contracts/verification/*`. Those tests must assert the
product surface itself, not verification internals.

## Concrete File Mapping

### Top-Level Harness

- move `/Users/jasl/Workspaces/Ruby/cybros/acceptance/` to
  `/Users/jasl/Workspaces/Ruby/cybros/verification/`
- rename the active namespace from `Acceptance` to `Verification`

### Repo Root Assets

- move `/Users/jasl/Workspaces/Ruby/cybros/Rakefile` to
  `/Users/jasl/Workspaces/Ruby/cybros/verification/Rakefile`
- move `/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/*` to
  `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/*`
- delete the now-empty repo-root `test/` tree if nothing product-owned remains

### Existing Harness Test Trees

- move `/Users/jasl/Workspaces/Ruby/cybros/acceptance/test/cli_support_test.rb`
  into `verification/test/support/` or `verification/test/contracts/`,
  depending on whether it remains a support test or a narrow contract test
- move `/Users/jasl/Workspaces/Ruby/cybros/acceptance/test/core_matrix_cli_ci_contract_test.rb`
  into `verification/test/contracts/`
- move `/Users/jasl/Workspaces/Ruby/cybros/acceptance/test/repo_licensing_contract_test.rb`
  into `verification/test/contracts/`
- reconcile duplicate CLI helper coverage currently split across
  `acceptance/test/cli_support_test.rb` and
  `core_matrix/test/lib/acceptance/cli_support_test.rb`, and keep only one
  verification-owned test copy

### `core_matrix` Harness Leaks

- move `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/lib/manual_acceptance/conversation_runtime_validation.rb`
  to `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/suites/e2e/conversation_runtime_validation.rb`
- remove bridge files such as
  `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/conversation_runtime_validation.rb`
  that only bounce back into product-owned paths

## Cleanup Rules

- do not keep compatibility wrappers, alias constants, or forwarding scripts for
  old `acceptance/...` paths
- do not keep acceptance-prefixed live env vars or scenario markers when a
  verification-prefixed equivalent is intended for the rebuilt surface
- delete tests that duplicate the same verification behavior in two places
- delete harness-owned code from product projects
- update or delete live docs that describe the old layout
- leave archived docs mostly untouched; instead, add a small historical note in
  archive index surfaces when needed

## Migration Strategy

### 1. Create The New Project Shell

- scaffold `verification/` with its own `Gemfile`, `Rakefile`, `README`, `bin`,
  `lib`, and `test`
- establish the `Verification` namespace

### 2. Move The Live Harness

- move the live `acceptance/` content into `verification/`
- reorganize internals into `adapters`, `support`, and `suites/e2e|perf|proof`

### 3. Move Repo-Root Verification Assets

- move root `Rakefile`
- move root `test/acceptance/*`

### 4. Move Product-Owned Harness Leaks

- move `core_matrix/lib/manual_acceptance/*`
- move `core_matrix/test/lib/acceptance/*`
- move `core_matrix/test/lib/manual_acceptance/*`
- leave `core_matrix/test/e2e/protocol/*` in place

### 5. Rewrite Live References

- update `.github/workflows/ci.yml`
- update `/Users/jasl/Workspaces/Ruby/cybros/.gitignore`
- update `/Users/jasl/Workspaces/Ruby/cybros/AGENTS.md`
- update live `README` files and docs indexes that still point at
  `acceptance/...`

### 6. Delete The Old Surface

- remove the old `acceptance/` directory
- remove repo-root verification leftovers
- remove obsolete product-owned harness helpers/tests

## Success Criteria

- there is one clear monorepo verification project:
  `/Users/jasl/Workspaces/Ruby/cybros/verification`
- a newcomer can understand the verification surface by reading only
  `verification/README.md`
- no live product code in `core_matrix` owns monorepo verification helper logic
- no live CI or developer instructions point at `acceptance/...`
- the active developer surface uses `verification`, `e2e`, `perf`, and `proof`
  consistently
- the migration is complete without compatibility shims
