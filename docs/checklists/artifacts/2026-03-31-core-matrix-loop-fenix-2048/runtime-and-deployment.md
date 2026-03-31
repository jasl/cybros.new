# Runtime And Deployment

## Stack Shape

- `Core Matrix` ran from the local Rails checkout in `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`.
- `Fenix` ran as the paired external runtime in Docker.
- The Fenix runtime base URL for this acceptance flow was `http://127.0.0.1:3101`.
- The mounted disposable runtime workspace on the host was `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix`.
- Inside the Fenix container that workspace was available at `/workspace`.

## Acceptance Run Identity

- Conversation public_id: `019d4354-7e5a-71f0-a981-4b037cb2659b`
- Turn public_id: `019d4354-7ee8-793a-8e04-b28410ffe2de`
- Workflow run public_id: `019d4354-7f45-728b-8f13-9a6388bbc0f8`
- Deployment public_id: `019d4353-98b2-75b2-86f2-fc7c04cce96b`
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
