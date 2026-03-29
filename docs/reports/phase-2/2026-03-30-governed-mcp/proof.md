# Governed Streamable HTTP MCP Invocation

- Date: 2026-03-30
- Operator: Codex
- Environment: bin/dev + fake Streamable HTTP MCP server
- Deployment Identifier: bundled:019d3b5a-a1a7-7319-ab30-9e26601fc8ec
- Runtime Mode: bundled
- Provider: dev
- Model: mock-model
- Workspace: 019d3b5a-a1d4-7ff3-8384-1890b94d8580
- Conversation: 019d3b5a-a201-711a-8432-6a2c5a7349da
- Turn: 019d3b5a-a27a-7ca4-b5ba-2738e5cec7eb
- WorkflowRun: 019d3b5a-a291-7e70-9914-10ae633ccc3d
- Node Count: 2
- Edge Count: 1
- Mermaid Artifact: ./run-019d3b5a-a291-7e70-9914-10ae633ccc3d.mmd

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
- failure_classification: transport
- failure_code: session_not_found
- tool_invocation_statuses: ["succeeded", "failed", "succeeded"]
- turn_lifecycle_state: active
- workflow_lifecycle_state: active
- workflow_wait_state: ready

## Operator Notes

The governed MCP path bound one echo tool over Streamable HTTP, recorded a durable session_not_found transport failure, reopened a new MCP session, and then completed successfully with echo: third.
