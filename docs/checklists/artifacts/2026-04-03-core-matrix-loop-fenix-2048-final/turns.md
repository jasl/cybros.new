# Capstone Turns

## Turn 1

- Scenario date: `2026-04-03`
- Operator: `Codex`
- Conversation `public_id`: `019d52db-08af-769a-b895-e84c541fc491`
- Turn `public_id`: `019d52db-08d6-7c2b-8934-9a9f05542a8a`
- Workflow-run `public_id`: `019d52db-08f9-70c1-8609-57261518d742`
- Agent program version `public_id`: `019d52da-ce01-7da4-9b6c-c48e27e8ed76`
- Execution runtime `public_id`: `019d52da-cdec-7834-850f-6eb59ea31d2d`
- Runtime mode: `Core Matrix host runtime + Dockerized Fenix`
- Provider handle: `openrouter`
- Model ref: `openai-gpt-5.4`
- API model: `openai-gpt-5.4`
- Selector: `candidate:openrouter/openai-gpt-5.4`
- Expected DAG shape: provider-backed `turn_step` with repeated `tool_call` and `barrier_join` expansion until completion
- Observed DAG shape:
  - `turn_step`: `28`
  - `tool_call`: `28`
  - `barrier_join`: `28`
  - Total workflow nodes: `84`
  - Highest observed provider round: `28`
- Expected conversation state: one user request followed by one completed agent response
- Observed conversation state:
  - Conversation lifecycle: `active`
  - Turn lifecycle: `completed`
  - Message roles: `user`, `agent`
  - Output message `public_id`: `019d52de-4864-7b9d-ab85-b7b19a613ee0`
- Subagent work expected: `yes`
- Subagent work observed: `no`
- Proof artifacts:
  - `acceptance-registration.json`
  - `capstone-run-bootstrap.json`
  - `skills-validation.json`
  - `host-playwright-verification.json`
  - `host-playability.png`
  - `export-roundtrip.md`
- Outcome: `pass`
