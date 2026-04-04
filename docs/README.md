# Documentation Index

## Directories

- [proposed-designs](/Users/jasl/Workspaces/Ruby/cybros/docs/proposed-designs/README.md): design drafts that are still under discussion
- [proposed-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/proposed-plans/README.md): early plan drafts that are not ready for activation
- [design](/Users/jasl/Workspaces/Ruby/cybros/docs/design/README.md): approved long-lived design baselines
- [future-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/README.md): accepted later-phase work that is intentionally not active yet
- [plans](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/README.md): active execution documents only
- [research-notes](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/README.md): technical investigations and retained conclusions
- [finished-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/README.md): completed plans that passed their verification gates
- [archived-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/archived-plans/README.md): superseded or historical material kept for traceability
- [checklists](/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/README.md): manual validation and verification checklists
- [operations](/Users/jasl/Workspaces/Ruby/cybros/docs/operations/queue-topology-and-provider-governor.md): runtime queue topology, scaling knobs, and durable provider admission guidance

## Current Truth

For the current implementation state, start here:

- active execution work:
  [docs/plans](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/README.md)
- current manual/product acceptance:
  [docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md)
- runtime-generated acceptance outputs:
  [acceptance/README.md](/Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md)
- completed, verified reset and product-shape changes:
  [docs/finished-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/README.md)

Many older design, research, report, and checklist records are intentionally
kept for traceability. Those records may preserve superseded naming from before
the April 2026 reset. The current codebase uses `AgentProgram`,
`AgentProgramVersion`, `AgentSession`, `ExecutionRuntime`, and
`ExecutionSession`.

## Lifecycle

Move work through the tree in this order:

`docs/proposed-designs` -> `docs/proposed-plans` -> `docs/future-plans` ->
`docs/plans` -> `docs/finished-plans` -> `docs/archived-plans`

Rules:

- keep approved design baselines in `docs/design`
- keep future but accepted work in `docs/future-plans`
- keep active execution documents in `docs/plans`
- move completed execution material into `docs/finished-plans`
- move replaced or obsolete material into `docs/archived-plans`

## Reference Handling

- Treat `references/` and external repositories as supporting material, not as
  durable documentation.
- When a design, plan, research note, or finished record uses a reference
  project for sanity checking, write the retained conclusion, tradeoff, or
  observed behavior directly into the local document.
- If a local document keeps a reference path or upstream URL, it should remain
  understandable even if the upstream material later moves or disappears.
