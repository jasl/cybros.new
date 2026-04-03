# Acceptance Reports

Use this directory for committed manual-validation proof artifacts from the
accepted backend loop baseline.

Recommended layout:

- `docs/reports/<collection>/YYYY-MM-DD-<scenario-slug>/proof.md`
- `docs/reports/<collection>/YYYY-MM-DD-<scenario-slug>/run-<workflow-run-id>.mmd`

Temporary exports may be generated elsewhere, but they do not count as formal
acceptance evidence until the artifact package is recorded here.

## Current Artifact Index (`2026-03-30`)

- `2026-03-30-bundled-fenix-fast-terminal`
- `2026-03-30-provider-backed-turn`
- `2026-03-30-human-interaction-wait-resume`
- `2026-03-30-subagent-wait-all`
- `2026-03-30-process-run-close-path`
- `2026-03-30-governed-tool`
- `2026-03-30-governed-mcp`
- `2026-03-30-deployment-rotation-upgrade`
- `2026-03-30-deployment-rotation-downgrade`
- `2026-03-30-external-fenix-validation`
- `2026-03-30-system-skill-deploy-flow`
- `2026-03-30-third-party-skill-activation`
- `2026-03-30-proof-export-package`

Scenario `03` during-generation steering is intentionally recorded in the
manual checklist and operator notes rather than a single proof package because
it validates multiple mutually exclusive control outcomes instead of one DAG.

To refresh a package, run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bundle exec ruby script/manual/workflow_proof_export.rb export ...
```

## Recommended `proof.md` Shape

```md
# <Scenario Title>

- Date: YYYY-MM-DD
- Environment: bin/dev
- Workspace: <workspace id or slug>
- Conversation: <conversation id>
- WorkflowRun: <workflow run id>
- Provider or Model Path: <provider/model ref>
- Node Count: <n>
- Edge Count: <n>
- Mermaid Artifact: ./run-<workflow-run-id>.mmd

## Expected Shape

- yield point: <short note>
- blocking barrier: <short note or none>
- successor agent step: <short note>
- presentation-policy note: <short note>

## Operator Notes

<brief observation of whether the graph matched the design>
```
