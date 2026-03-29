# Governed Tool Invocation

- Date: 2026-03-30
- Operator: Codex
- Environment: bin/dev + governed tool validation script
- Deployment Identifier: bundled:019d3b5b-55aa-7191-8479-b12e99b9abd4
- Runtime Mode: bundled
- Provider: dev
- Model: mock-model
- Workspace: 019d3b5b-55d9-71d3-ba39-09ee42bcf716
- Conversation: 019d3b5b-5605-7efc-ab51-5221884e855a
- Turn: 019d3b5b-567a-7541-9887-04b65c52679f
- WorkflowRun: 019d3b5b-5691-755f-a4e6-18569af7f79c
- Node Count: 2
- Edge Count: 1
- Mermaid Artifact: ./run-019d3b5b-5691-755f-a4e6-18569af7f79c.mmd

## Expected DAG Shape
- root->agent_turn_step

## Observed DAG Shape
- root->agent_turn_step

## Expected Conversation State
- conversation_state: active
- turn_lifecycle_state: active
- workflow_lifecycle_state: active
- workflow_wait_state: ready

## Observed Conversation State
- conversation_state: active
- tool_binding_id: 019d3b5b-56ea-7faa-b1e6-644e70193f4f
- tool_invocation_id: 019d3b5b-56fd-78e4-a6bc-fbe263e884b1
- tool_invocation_status: succeeded
- turn_lifecycle_state: active
- workflow_lifecycle_state: active
- workflow_wait_state: ready

## Operator Notes

The governed reserved tool path created one durable binding and one durable invocation, then spawned a subagent successfully through the reserved tool contract.
