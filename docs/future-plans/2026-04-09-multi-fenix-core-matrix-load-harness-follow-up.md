# Multi-Fenix Load Harness Follow-Up

## Why This Exists

The April 9, 2026 implementation and verification run delivered a working
acceptance-embedded load harness with successful local `smoke`,
`target_8_fenix`, and `stress` executions. The required metric sample families
are now present, but the heavier pressure profiles still rely on descriptive
latency baselines rather than hardened threshold budgets.

## Verified Baselines

### Smoke

- artifact stamp: `2026-04-10-023428-multi-fenix-core-matrix-load-smoke`
- runtime count: `2`
- completed workload items: `4`
- duration seconds: `32.904`
- throughput items per minute: `7.294`
- turn latency `p95_ms`: `2183.479`
- CoreMatrix poll latency `p95_ms`: `14.879`

### Target 8 Fenix

- artifact stamp: `2026-04-10-022952-multi-fenix-core-matrix-load-target-8-fenix`
- runtime count: `8`
- completed workload items: `16`
- duration seconds: `104.877`
- throughput items per minute: `9.154`
- turn latency `p95_ms`: `7220.285`
- Fenix poll latency `p95_ms`: `118.946`
- CoreMatrix poll latency `p95_ms`: `6.476`
- mailbox lease latency `count`: `16`
- queue pressure sample count: `16`
- database checkout sample count: `57389`

### Stress

- artifact stamp: `2026-04-10-022610-multi-fenix-core-matrix-load-stress`
- runtime count: `8`
- completed workload items: `16`
- duration seconds: `147.132`
- throughput items per minute: `6.525`
- turn latency `p95_ms`: `43172.621`
- mailbox exchange wait `p95_ms`: `256.235`
- queue pressure sample count: `32`
- database checkout sample count: `78739`

## Residual Risks

- `target_8_fenix` and `stress` now both produce the required metric samples and
  run as local pressure gates, but neither profile has hardened latency SLO
  thresholds yet.
- `target_8_fenix` intentionally validates queued Fenix runtime-control
  execution; `stress` intentionally validates provider-backed mailbox exchange
  pressure. Their latency signatures are different and should not share one
  generic regression threshold.
- `stress` remains the best profile for catching provider-backed mailbox
  exchange regressions, but its queue delay and turn latency numbers are still
  useful local capacity signals rather than default CI budgets.

## Recommended Next Threshold Work

1. Run repeated local batches for `target_8_fenix` and `stress`, then derive
   per-profile p95/p99 regression budgets instead of using sample presence alone.
2. Split queue-delay budgeting by queue family:
   `runtime_control` for `target_8_fenix`, `llm_dev` or later provider queues
   for `stress`.
3. Decide whether `target_8_fenix` should become a non-default CI gate or stay
   local-only with a nightly schedule once repeated latency baselines stabilize.
4. Keep `stress` local-only until queue-delay and turn-latency variance narrow
   enough to avoid noisy failures.
