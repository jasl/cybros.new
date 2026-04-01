# Capstone Turns

## Turn 1

- Scenario date: `2026-04-01`
- Operator: `Codex`
- Conversation `public_id`: `019d49d5-0b2d-7768-b776-3b85d867fa0b`
- Turn `public_id`: `019d49d5-0bba-74ec-a525-be28d4c7e84b`
- Workflow-run `public_id`: `019d49d5-0c13-7c62-889f-d3988ae272a7`
- Deployment `public_id`: `019d49d0-3ce2-773e-a3fe-fd438ba097bc`
- Execution environment `public_id`: `019d49d0-3ccf-7280-b65d-c2233c9f178f`
- Runtime mode: `Core Matrix` host runtime + Dockerized `Fenix`
- Provider handle: `openrouter`
- Model ref: `openai-gpt-5.4`
- API model: `openai/gpt-5.4`
- Expected DAG shape: provider-backed `turn_step` with repeated `tool_call` and `barrier_join` expansion until completion
- Observed DAG shape:
  - `turn_step`: `30`
  - `tool_call`: `31`
  - `barrier_join`: `31`
  - Total workflow nodes: `92`
  - Highest observed provider round: `30`
- Expected conversation state: one user request followed by one completed agent response
- Observed conversation state:
  - Conversation lifecycle: `active`
  - Turn lifecycle: `completed`
  - Message roles: `user`, `agent`
  - Output message `public_id`: `019d49da-f92c-72c8-846f-f7b628e41306`
- Subagent work expected: `yes`
- Subagent work observed: `yes`
  - Observed subagent session `public_id`: `019d49d5-8271-779e-bd21-9345c8d64d8d`
  - Observed subagent profile: `researcher`
- Proof artifacts:
  - `acceptance-registration.json`
  - `skills-validation.json`
  - `capstone-run-bootstrap.json`
  - `host-playwright-verification.json`
  - `host-playability.png`
- Outcome: `pass`
