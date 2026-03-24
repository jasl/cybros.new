# Documentation Index

## Directories

- [design](/Users/jasl/Workspaces/Ruby/cybros/docs/design/README.md): long-lived design baselines, protocol notes, and phase-shaping decisions
- [plans](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/README.md): executable phase, milestone, task-group, and task documents
- [research-notes](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/README.md): technical investigations, library evaluations, and option analysis that should stay understandable without reopening external references
- [finished-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/README.md): completed execution plans and milestones that have passed their stage-level acceptance checks
- [future-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/README.md): deferred follow-up and roadmap documents
- [archived-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/archived-plans/README.md): superseded, withdrawn, or historical plan material kept only for traceability
- [checklists](/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/README.md): manual validation and verification checklists

## Lifecycle

- Keep active execution documents in `docs/plans`.
- Keep technical investigations and library comparisons in `docs/research-notes`, and write the actual conclusions there instead of depending on `references/`.
- Keep not-yet-activated follow-up work in `docs/future-plans`.
- Move a plan or milestone into `docs/finished-plans` only after implementation is complete and its required verification gates pass.
- Move obsolete or replaced material into `docs/archived-plans` instead of mixing it with active execution documents.

## Reference Handling

- Treat `references/` and external repositories as supporting material, not as durable documentation.
- When a design, plan, research note, or finished record uses a reference project for sanity checking, write the retained conclusion, tradeoff, or observed behavior directly into the local document.
- If a local document keeps a reference path or upstream URL, it should be an index pointer only. The document should still remain understandable if that reference later moves, changes, or disappears.
