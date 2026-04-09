# Multi-Fenix Load Harness Follow-Up

## Why This Exists

The April 9, 2026 implementation and verification run delivered a working
acceptance-embedded load harness with successful local `smoke`,
`target_8_fenix`, and `stress` executions. The required metric sample families
are now present, but the heavier pressure profiles still rely on descriptive
latency baselines rather than hardened threshold budgets.

## Verified Baselines

### Smoke

- artifact stamp: `2026-04-10-002125-multi-fenix-core-matrix-load-smoke`
- runtime count: `2`
- completed workload items: `4`
- duration seconds: `33.362`
- turn latency `p95_ms`: `2088.111`
- CoreMatrix poll latency `p95_ms`: `13.242`

### Target 8 Fenix

- artifact stamp: `2026-04-10-002206-multi-fenix-core-matrix-load-target-8-fenix`
- runtime count: `8`
- completed workload items: `16`
- duration seconds: `103.871`
- throughput items per minute: `9.242`
- turn latency `p95_ms`: `6915.602`
- Fenix poll latency `p95_ms`: `119.906`
- CoreMatrix poll latency `p95_ms`: `17.268`
- mailbox lease latency `count`: `16`
- queue pressure sample count: `16`
- database checkout sample count: `55794`

### Stress

- artifact stamp: `2026-04-10-001821-multi-fenix-core-matrix-load-stress`
- runtime count: `8`
- completed workload items: `16`
- duration seconds: `164.524`
- throughput items per minute: `5.835`
- turn latency `p95_ms`: `43223.04`
- mailbox exchange wait `p95_ms`: `775.873`
- queue pressure sample count: `16`
- database checkout sample count: `79484`

## Residual Risks

- `target_8_fenix` and `stress` now both produce the required metric samples,
  but neither profile has hardened latency SLO thresholds yet.
- `target_8_fenix` intentionally validates queued Fenix runtime-control
  execution; `stress` intentionally validates provider-backed mailbox exchange
  pressure. Their latency signatures are different and should not share one
  generic regression threshold.
- `stress` is still a local-only pressure gate because its queue delay and turn
  latency numbers are useful capacity signals, but not yet stable enough to be
  promoted into default CI budgets.

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
