# Reports

This directory stores committed operator-facing validation evidence.

Use it for durable proof artifacts that should stay in the repository after a
manual validation pass, not for ad hoc local debugging output.

## Workflow Proof Artifacts

Store workflow-proof packages under a dated acceptance collection in this
directory.

Recommended package shape:

- `docs/reports/<collection>/YYYY-MM-DD-<scenario-slug>/`

Each package should usually contain:

- `proof.md`
- one or more `run-<workflow-run-id>.mmd` Mermaid files

The committed `2026-03-30` acceptance set currently includes proof
packages for:

- bundled `Fenix` fast terminal
- real provider-backed bundled turn
- human-interaction wait and resume
- subagent `wait_all`
- `process_run` close path
- governed tool
- governed Streamable HTTP MCP
- deployment rotation upgrade and downgrade
- independent external `Fenix`
- built-in system skill deploy flow
- third-party skill activation
- the reusable proof-export package itself

See the collection README files in this directory for scenario-level package
indexes and recommended `proof.md` structure.

Temporary exports may still be generated under `tmp/`, but they do not count as
formal acceptance evidence until the relevant artifact package is recorded
here.
