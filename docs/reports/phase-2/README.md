# Phase 2 Reports

Use this directory for committed Phase 2 manual-validation proof artifacts.

Recommended layout:

- `docs/reports/phase-2/YYYY-MM-DD-<scenario-slug>/proof.md`
- `docs/reports/phase-2/YYYY-MM-DD-<scenario-slug>/run-<workflow-run-id>.mmd`

Temporary exports may be generated elsewhere, but they do not count as formal
acceptance evidence until the artifact package is recorded here.

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
