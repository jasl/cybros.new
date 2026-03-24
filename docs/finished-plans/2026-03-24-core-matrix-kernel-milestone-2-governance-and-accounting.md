# Core Matrix Kernel Milestone 2: Governance And Accounting

Use this milestone index together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/future-plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

This milestone owns Task Groups 05-06 and their child tasks:

- [Task Group 05: Build The Config-Backed Provider Catalog And Governance Models](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-group-05-provider-catalog-and-governance.md)
- [Task 05.1: Add Provider Catalog Config And Validation](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-05-1-provider-catalog-config.md)
- [Task 05.2: Add Provider Governance Models And Services](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-05-2-provider-governance-models.md)
- [Task Group 06: Build Usage Accounting, Rollups, And Execution Profiling Facts](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-group-06-usage-accounting-and-profiling.md)
- [Task 06.1: Add Usage Events And Rollups](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-06-1-usage-events-and-rollups.md)
- [Task 06.2: Add Execution Profiling Facts](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-06-2-execution-profiling-facts.md)

Milestone goals:

- build the config-backed provider catalog and governance surfaces
- land the model-role catalog and related resolution prerequisites
- build usage accounting, rollups, and profiling facts before runtime execution resources start writing into them

Execution rules:

- execute the task documents in order
- load only the active execution-unit document during implementation
- treat this file as the milestone ordering index, not as the detailed task body
- apply the shared guardrails and execution-gate audits from the implementation-plan index after every task
- if a child task consults `references/` or external implementations, write the retained conclusion into that task document and any local docs it updates; do not leave only a bare reference path behind

## Completion Record

- status:
  completed on `2026-03-24` on branch `codex/phase1`
- landing commits:
  - Task 05.1: `6074088` `feat: add provider catalog config validation`
  - Task 05.2: `2cc4bc4` `feat: add provider governance models`
  - Task 06.1: `92d1dca` `feat: add provider usage events and rollups`
  - Task 06.2: `8c74487` `feat: add execution profiling facts`
- landed milestone scope:
  - added the config-backed provider, model, and model-role catalog with boot-time validation
  - added installation-scoped provider credentials, entitlements, policies, and audited mutation services
  - added usage-event truth plus rollup projection for provider accounting
  - added execution profiling facts as a separate runtime telemetry surface
- verification evidence:
  - child task records retain the exact targeted acceptance commands for Tasks 05.1, 05.2, 06.1, and 06.2
  - `cd core_matrix && bin/brakeman --no-pager` reported `0` warnings during the `2026-03-25` archival review rerun
  - `cd core_matrix && bin/bundler-audit` reported no vulnerabilities during the same rerun
  - `cd core_matrix && bin/rubocop -f github` passed during the same rerun
  - `cd core_matrix && bun run lint:js` passed during the same rerun
  - `cd core_matrix && bin/rails db:test:prepare test` passed with `111 runs, 486 assertions, 0 failures, 0 errors`
  - `cd core_matrix && bin/rails db:test:prepare test:system` passed with `0 runs, 0 assertions, 0 failures, 0 errors`
- retained findings:
  - provider catalog state stays config-backed while mutable installation governance facts stay in SQL
  - provider billing facts and generic execution telemetry stay in separate storage surfaces
  - no non-authoritative reference project overrode the local design or behavior docs for this milestone
- carry-forward notes:
  - later selector-resolution and runtime execution work should read the provider catalog and governance rows without collapsing them into one aggregate
  - later quota or reporting work should keep treating `UsageEvent` as detailed truth and `UsageRollup` as projection
  - later runtime-resource work may reference profiling facts, but should not repurpose them as provider billing rows
