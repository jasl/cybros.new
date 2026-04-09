# Multi-Fenix Load Harness Follow-Up

## Why This Exists

The April 9, 2026 implementation and verification run delivered a working
acceptance-embedded load harness with successful local `smoke` and
`target_8_fenix` executions, but the current deterministic workload does not
yet generate meaningful pressure samples for every metric family we wired.

## Verified Baselines

### Smoke

- artifact stamp: `2026-04-09-task8-wrapper-smoke-v3`
- runtime count: `2`
- completed workload items: `4`
- duration seconds: `9.01`
- turn latency `p95_ms`: `2020.631`
- CoreMatrix poll latency `p95_ms`: `10.972`

### Target 8 Fenix

- artifact stamp: `2026-04-09-task9-target-8-fenix-v1`
- runtime count: `8`
- completed workload items: `16`
- duration seconds: `33.018`
- throughput items per minute: `29.075`
- turn latency `p95_ms`: `6761.269`
- Fenix poll latency `p95_ms`: `149.401`
- CoreMatrix poll latency `p95_ms`: `5.614`

## Residual Risks

- `mailbox_lease_latency` remained empty in the verified baseline artifacts
- `mailbox_exchange_wait` remained empty in the verified baseline artifacts
- `queue_pressure.max_queue_delay_ms` stayed `null` and queue sample maps stayed
  empty in the verified baseline artifacts
- `database_checkout_pressure.checkout_wait` stayed empty while
  `timeout_count` remained `0`

These are not wiring failures. The event fields are present, the artifact
bundles are complete, and the sinks write to the correct files. The issue is
that the deterministic workload is still too light and too narrow to trigger
meaningful contention for those metric families.

## Recommended Next Threshold Work

1. Add a follow-up workload profile that increases mailbox contention without
   introducing browser or workspace mutation side effects.
2. Add a provider-backed or queue-heavier profile only after the deterministic
   profile remains stable, so queue and DB pressure metrics can be observed
   under controlled load.
3. Keep `smoke` as a correctness gate candidate, but keep `target_8_fenix`
   local-only until at least one heavier profile yields non-empty mailbox,
   queue, and DB pressure samples.
4. When those samples exist, derive alert thresholds from stable repeated local
   baselines instead of using the first-run numbers as hard CI gates.
