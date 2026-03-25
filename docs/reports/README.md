# Reports

This directory stores committed operator-facing validation evidence.

Use it for durable proof artifacts that should stay in the repository after a
manual validation pass, not for ad hoc local debugging output.

## Phase 2 Workflow Proof Artifacts

Phase 2 should store workflow-proof packages under:

- `docs/reports/phase-2/YYYY-MM-DD-<scenario-slug>/`

Each package should usually contain:

- `proof.md`
- one or more `run-<workflow-run-id>.mmd` Mermaid files

Temporary exports may still be generated under `tmp/`, but they do not count as
formal acceptance evidence until the relevant artifact package is recorded
here.
