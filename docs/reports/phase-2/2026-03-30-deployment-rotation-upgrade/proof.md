# Same-Installation Deployment Rotation Upgrade

- Date: 2026-03-30
- Operator: Codex
- Environment: bin/dev + AGENT_FENIX_PORT=3101 bin/dev
- Deployment Identifier: bundled:019d3b70-7e22-7e64-a943-d3f80df0e275
- Runtime Mode: bundled
- Provider: dev
- Model: mock-model
- Workspace: 019d3b70-7d39-7b0a-a9a4-33d0c4b23083
- Conversation: 019d3b70-7d42-7ed2-bea0-6acd75f99094
- Turn: 019d3b70-7e4e-7d47-961b-add458670335
- WorkflowRun: 019d3b70-7e61-7f04-bfe2-858c0a60edc5
- Node Count: 1
- Edge Count: 0
- Mermaid Artifact: ./run-019d3b70-7e61-7f04-bfe2-858c0a60edc5.mmd

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

The same conversation was rebound from bundled Fenix v1 to v2 inside one execution environment, then a new provider-backed turn completed successfully under the upgraded deployment.
