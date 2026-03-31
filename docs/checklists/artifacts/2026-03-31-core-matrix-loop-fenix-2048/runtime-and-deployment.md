# Runtime And Deployment

## Stack Shape

- `Core Matrix` ran from the local Rails checkout in `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`.
- `Fenix` ran as the paired external runtime in Docker.
- The Fenix runtime base URL for this acceptance flow was `http://127.0.0.1:3101`.
- The mounted disposable runtime workspace on the host was `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix`.
- Inside the Fenix container that workspace was available at `/workspace`.

## Acceptance Run Identity

- Conversation public_id: `019d4128-1484-760a-8c8c-6d0e436e575e`
- Turn public_id: `019d4128-14cb-7d93-ba34-32cc61dc8794`
- Workflow run public_id: `019d4128-1505-746e-b133-d875960c5e20`
- Deployment public_id: `019d411d-1ee3-7133-b5d9-551cbbd854ee`
- Provider handle: `openrouter`
- Model ref: `openai-gpt-5.4-live-acceptance`
- API model: `openai/gpt-5.4`
- Workflow state: `completed`
- Turn state: `completed`
- Loop settings: `max_rounds=64`

## Verified Responsibility Split

- `Core Matrix` owned the real provider call, repeated round control, tool routing, workflow node completion, and exported proof.
- `Fenix` owned per-round prompt construction, skill selection, and execution of Fenix-owned tools such as workspace, browser, and command helpers.
- This run therefore validates the intended design that `Core Matrix` and `Fenix` are fully orthogonal and fully complementary. Neither side needed to absorb the other's core responsibility.

## Browser Runtime Endpoints Used

- In-agent app verification URL: `http://127.0.0.1:4173`
- Host-side verification URL: `http://127.0.0.1:4174`
- Exported Fenix browser screenshot: `fenix-browser-screenshot.png`

## Primary Proof Artifact

- Full exported run data: `run-summary.json`
