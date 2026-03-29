# turn_command ProcessRun Close Path

- Date: 2026-03-30
- Operator: Codex
- Environment: bin/dev + rails runner interrupt/close reports
- Deployment Identifier: bundled:019d3b59-d401-7e3c-a1cf-42bee31480dd
- Runtime Mode: bundled
- Provider: openrouter
- Model: openai-gpt-5.4
- Workspace: 019d3b59-d426-76d4-921f-2fde38c3b7a6
- Conversation: 019d3b59-d436-71e9-a1c1-8f7ca0913a16
- Turn: 019d3b59-d4b4-7681-bfe3-191800df4355
- WorkflowRun: 019d3b59-d4fa-73f3-b307-abc975c8de45
- Node Count: 2
- Edge Count: 1
- Mermaid Artifact: ./run-019d3b59-d4fa-73f3-b307-abc975c8de45.mmd

## Expected DAG Shape
- root->process

## Observed DAG Shape
- root->process

## Expected Conversation State
- conversation_lifecycle_state: active
- process_close_outcome_kind: graceful
- process_close_state: closed
- process_lifecycle_state: stopped
- turn_lifecycle_state: canceled
- workflow_lifecycle_state: canceled
- workflow_wait_state: ready

## Observed Conversation State
- close_request_status: completed
- conversation_lifecycle_state: active
- process_close_outcome_kind: graceful
- process_close_state: closed
- process_lifecycle_state: stopped
- process_run_id: 019d3b59-d524-7cc7-a09d-256a5394e42c
- turn_lifecycle_state: canceled
- workflow_lifecycle_state: canceled
- workflow_wait_state: ready

## Operator Notes

A turn_command ProcessRun was started on workflow node process, fenced via RequestTurnInterrupt, and then closed through an environment-plane resource_closed report. The workflow and turn ended canceled while the ProcessRun ended stopped/closed with graceful outcome.
