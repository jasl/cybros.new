# Same-Installation Deployment Rotation Downgrade

- Date: 2026-03-30
- Operator: Codex
- Environment: bin/dev + AGENT_FENIX_PORT=3101 bin/dev
- Deployment Identifier: bundled:019d3b70-7ea8-7885-80fe-cfb89a0d6069
- Runtime Mode: bundled
- Provider: dev
- Model: mock-model
- Workspace: 019d3b70-7d39-7b0a-a9a4-33d0c4b23083
- Conversation: 019d3b70-7d42-7ed2-bea0-6acd75f99094
- Turn: 019d3b70-7ed6-7795-bfed-e7d49042aea7
- WorkflowRun: 019d3b70-7eed-71b4-9fb2-47f446801f38
- Node Count: 1
- Edge Count: 0
- Mermaid Artifact: ./run-019d3b70-7eed-71b4-9fb2-47f446801f38.mmd

## Expected DAG Shape
- turn_step

## Observed DAG Shape
- turn_step

## Expected Conversation State
- conversation_state: active
- turn_lifecycle_state: completed
- workflow_lifecycle_state: completed
- workflow_wait_state: ready

## Observed Conversation State
- conversation_state: active
- turn_lifecycle_state: completed
- workflow_lifecycle_state: completed
- workflow_wait_state: ready

## Operator Notes

The same conversation was rebound again from bundled Fenix v2 down to v0.9 inside the retained execution environment, and the next provider-backed turn completed cleanly under the downgraded deployment.
