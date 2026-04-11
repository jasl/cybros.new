# Provider Transport Pooling and llm_dev Retuning Design

**Date:** 2026-04-10

## Goal

Improve provider-backed throughput and heavy-load latency without changing the CoreMatrix/Fenix external protocol or replacing the current `SimpleInference` stack.

## Current Findings

- The earlier throughput wave already landed the high-value mailbox changes: deferred agent mailbox exchange and materialized mailbox routing are present in the active codebase.
- Real provider paths still build `SimpleInference::HTTPAdapters::Default`, which uses `Net::HTTP` instead of the vendored persistent `HTTPX` adapter.
- The `openai-ruby` reference is useful mainly because it confirms the value of a long-lived client, pooled connections, and explicit retry/timeout policy. Those same wins are available in the existing `SimpleInference::HTTPAdapters::HTTPX` implementation.
- The current `llm_dev` queue baseline is still conservative relative to the verified `8 Fenix` host target.

## Design Direction

### 1. Move real provider traffic to pooled HTTPX

Keep `SimpleInference` as the provider abstraction, but route the real provider adapter keys through the vendored persistent `HTTPX` adapter instead of `Net::HTTP`.

Scope:

- `codex_subscription_responses`
- `openai_responses`
- `openrouter_chat_completions`
- `local_openai_compatible_chat_completions`
- mock adapters stay on the cheap default adapter unless tests prove they also need pooling

This preserves the existing provider contracts while removing needless connection setup overhead from provider-backed turns.

### 2. Re-tune the `llm_dev` queue baseline

After the transport change is real, raise the `llm_dev` queue defaults to better match the verified `8`-core baseline. This is a queue-topology change, not a correctness change, so it should be driven by perf/config tests and acceptance perf runs.

The first pass should stay conservative enough to avoid starving orchestration queues. The goal is lower queue delay, not simply more threads.

## Out of Scope

- replacing `SimpleInference` with `openai-ruby`
- changing provider request/response contracts
- changing admission control policies
- changing the database or job backend
- turning local perf gates into CI budgets

## Acceptance

This wave is complete when:

- real provider adapter keys resolve to pooled `HTTPX`
- config/perf tests document the updated `llm_dev` baseline
- `smoke`, `target_8_fenix`, and `stress` still pass
- provider-backed throughput or queue delay improves measurably relative to the April 10 baseline
- documentation reflects the updated transport and queue semantics
