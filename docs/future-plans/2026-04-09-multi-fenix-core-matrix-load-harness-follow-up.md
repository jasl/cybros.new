# Multi-Fenix Load Harness Follow-Up

## Why This Exists

The April 9, 2026 implementation and verification run delivered a working
acceptance-embedded load harness with successful local `smoke`,
`target_8_fenix`, and `stress` executions. The required metric sample families
are now present, but the heavier pressure profiles still rely on descriptive
latency baselines rather than hardened threshold budgets.

## Verified Baselines

The latest local baselines below reflect the April 10 transport-pooling and
`llm_dev` retuning wave. One important caveat remains: the current `stress`
profile uses the `role:mock` workload and therefore measures `llm_dev` queue
pressure and mailbox exchange behavior, not a pure OpenAI/OpenRouter transport
throughput path.

### Smoke

- artifact stamp: `2026-04-10-035552-multi-fenix-core-matrix-load-smoke`
- runtime count: `2`
- completed workload items: `4`
- duration seconds: `37.214`
- throughput items per minute: `6.449`
- turn latency `p95_ms`: `2348.858`
- CoreMatrix poll latency `p95_ms`: `8.257`

### Target 8 Fenix

- artifact stamp: `2026-04-10-035640-multi-fenix-core-matrix-load-target-8-fenix`
- runtime count: `8`
- completed workload items: `16`
- duration seconds: `100.125`
- throughput items per minute: `9.588`
- turn latency `p95_ms`: `7417.038`
- Fenix poll latency `p95_ms`: `150.661`
- CoreMatrix poll latency `p95_ms`: `7.044`
- mailbox lease latency `count`: `16`
- queue pressure sample count: `16`
- database checkout sample count: `56806`

### Stress

- artifact stamp: `2026-04-10-035835-multi-fenix-core-matrix-load-stress`
- runtime count: `8`
- completed workload items: `16`
- duration seconds: `134.323`
- throughput items per minute: `7.147`
- turn latency `p95_ms`: `43317.272`
- mailbox exchange wait `p95_ms`: `240.289`
- queue pressure sample count: `32`
- database checkout sample count: `71575`

## Residual Risks

- `target_8_fenix` and `stress` now both produce the required metric samples and
  run as local pressure gates, but neither profile has hardened latency SLO
  thresholds yet.
- `target_8_fenix` intentionally validates queued Fenix runtime-control
  execution; `stress` intentionally validates provider-backed mailbox exchange
  pressure. Their latency signatures are different and should not share one
  generic regression threshold.
- `stress` remains the best local profile for catching `llm_dev` queue pressure
  and mailbox-exchange regressions, but it is not yet the right benchmark if we
  want to isolate transport-level wins for OpenAI/OpenRouter requests.

## Recommended Next Threshold Work

1. Run repeated local batches for `target_8_fenix` and `stress`, then derive
   per-profile p95/p99 regression budgets instead of using sample presence alone.
2. Split queue-delay budgeting by queue family:
   `runtime_control` for `target_8_fenix`, `llm_dev` for the current `stress`
   profile, and add a separate real-provider profile before setting transport
   budgets for OpenAI/OpenRouter.
3. Decide whether `target_8_fenix` should become a non-default CI gate or stay
   local-only with a nightly schedule once repeated latency baselines stabilize.
4. Keep `stress` local-only until queue-delay and turn-latency variance narrow
   enough to avoid noisy failures.
