# Core Matrix Phase 2 Runtime Loop And MCP Research Note

## Status

Recorded research for future `Core Matrix` and `Fenix` Phase 2 planning.

This note captures durable conclusions from the local legacy implementation,
`simple_inference`, and the local Ruby MCP SDK reference. It should remain
useful even if `references/` changes later.

## Decision Summary

- Do not restore prompt building as a `Core Matrix` kernel responsibility.
- Preserve execution-time budget and context hints as a runtime contract for
  agents rather than as kernel-owned prompt assembly.
- Split token-related controls into hard kernel or provider limits versus
  advisory runtime hints.
- Preserve a stage-shaped agent customization surface equivalent to the
  legacy lifecycle hooks:
  - `prepare_turn`
  - `compact_context`
  - `review_tool_call`
  - `project_tool_result`
  - `finalize_output`
  - `handle_error`
- Keep the helper surface small and explicit:
  - `estimate_tokens`
  - `estimate_messages`
- Treat context compaction, summary generation, and tool-result projection as
  agent concerns in Phase 2 unless the kernel must enforce a policy
  boundary.
- Treat provider- or tool-returned usage as the authoritative token-usage fact
  when available; agent-side estimates remain advisory.
- Use `core_matrix/vendor/simple_inference` as the shared provider-execution
  substrate for Phase 2 instead of building a second provider HTTP layer.
- Implement Streamable HTTP MCP as a session-aware client transport in
  `Core Matrix`; do not try to adopt the upstream server transport wholesale.

## Stable Findings From Legacy Cybros Runtime

The most valuable patterns in the local legacy `cybros` implementation are not
its prompt-building internals. They are its execution-time boundaries.

Durable patterns worth keeping:

- explicit context-window checks plus reserved-output-token budgeting before a
  model request is sent
- soft-threshold-style context warnings that can recommend compaction without
  forcing the kernel to own one universal compaction strategy
- provider-returned usage facts persisted separately from advisory local
  estimates so later accounting and context-budget advice can rely on the best
  available ground truth
- a small runtime-surface lifecycle rather than one monolithic "run the agent"
  callback
- minimal helper injection for token and message estimation
- stage-level timeout and output-size limits
- provider request correlation through generated request identifiers
- explicit tool-result projection and context-compaction phases
- explicit error-handling phase instead of letting every provider or tool error
  leak through the same ad hoc path

The local legacy context-management code also reinforces an important boundary:

- tool-output pruning and summarization are best treated as strategies that can
  vary by agent
- the kernel should persist execution context and governance facts, but it does
  not need to own one universal compaction algorithm in Phase 2

## What To Preserve Without Restoring Prompt Building

Moving prompt building out of `Core Matrix` should simplify Phase 2, but it
should not collapse the runtime into a black box.

Phase 2 should keep a small execution-advisory contract available to agent
programs or their SDK layer:

- execution context assembled by the kernel
- token and message estimation helpers
- the most likely model or model-profile hint for the upcoming request
- context-window and reserved-output budget hints
- advisory compaction-threshold hints derived from the current provider or model
  budget policy
- stable request or invocation correlation IDs
- stage-shaped hook entry points around turn preparation, compaction, tool
  review, tool-result projection, output finalization, and error handling

This contract should remain advisory. The kernel uses it to support
customization and accounting, not to take prompt-building ownership back from
the agent.

Recommended split:

- `Core Matrix` owns hard budget lines such as provider or policy-enforced
  output ceilings, timeout ceilings, and authoritative usage accounting
- the agent owns proactive estimation, preflight prompt sizing, and
  voluntary `compact_context` behavior before a request is sent
- after a provider response returns, `Core Matrix` may evaluate advisory
  compaction-threshold crossings using the authoritative usage numbers it now
  has, but this remains a hint or follow-up signal rather than a retroactive
  execution failure
- when the kernel knows the likely model or model profile before prompt
  construction, it should expose that hint to the agent so local
  token-estimation strategy can adapt before the request is sent

## Stable Findings From SimpleInference

`core_matrix/vendor/simple_inference` already provides most of the provider
transport shape that Phase 2 needs.

Durable findings:

- it already supports both OpenAI-compatible chat-completions style calls and
  the OpenAI Responses API
- it already supports SSE streaming for both chat-style and Responses-style
  execution paths
- the Responses protocol can fall back to normal JSON responses when the server
  does not return a stream
- it normalizes output text and usage into a reusable Ruby-facing contract
- its protocol layer already centralizes JSON handling, HTTP failure handling,
  and timeout or connection errors

Phase 2 should therefore treat `simple_inference` as the provider execution
substrate and extend it only where the loop actually needs more protocol
support.

## Stable Findings From The Ruby MCP SDK

The local Ruby MCP SDK reference is most useful for Streamable HTTP transport
shape, especially session management.

Durable findings:

- session-oriented Streamable HTTP uses a `POST initialize` request that
  returns `Mcp-Session-Id`
- the client then opens a `GET` SSE stream using that same session id
- later JSON-RPC requests continue over `POST` with the same session id
- session teardown uses `DELETE` with the same session id
- session-not-found handling is part of the transport semantics rather than an
  application-level special case
- the upstream generic HTTP client is not enough for Streamable HTTP SSE by
  itself; the example client and transport code are more useful than the
  non-streaming helper

Phase 2 should therefore implement a small client-side Streamable HTTP MCP
transport in `Core Matrix` rather than trying to embed the server-side SDK
transport.

## Phase 2 Planning Consequences

These findings imply a narrow Phase 2 adoption shape:

- `Core Matrix` owns the loop executor, workflow progression, policy
  enforcement, and invocation supervision
- `Core Matrix` may own provider execution transport through
  `simple_inference`, but not prompt building
- `Core Matrix` should expose execution budget and correlation hints so agent
  programs can customize compaction and preparation
- `Fenix` should preserve runtime-stage hooks for both deterministic and
  LLM-driven behavior
- Streamable HTTP MCP should enter the same governed capability path as other
  tools, with session-aware supervision and failure recording
- manual validation for Phase 2 should include at least one real Streamable
  HTTP MCP-backed tool path

## Re-Evaluation Triggers

Re-open this note when one of these becomes true:

- `Core Matrix` starts taking prompt-building ownership back from agent
  programs
- multiple agents need a shared SDK for runtime-stage hooks and budget
  helpers
- the loop needs richer provider-native event handling than the current
  `simple_inference` contracts expose
- Streamable HTTP MCP is no longer the first MCP transport the kernel needs to
  support
- a later phase wants the kernel to own compaction or summarization policy

## Reference Index

These references informed the note, but they are not the source of truth.

Local monorepo references:

- [/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/directives/runner.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/directives/runner.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/runtime_surface.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/runtime_surface.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/runtime_surface/runner.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/runtime_surface/runner.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/runtime_surface/helpers.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/runtime_surface/helpers.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/runtime_surface/inputs.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/runtime_surface/inputs.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/context_management/tool_output_pruner.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/context_management/tool_output_pruner.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/context_management/summarizer.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/context_management/summarizer.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/mcp/client.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/mcp/client.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/mcp/json_rpc_client.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/agent_core/mcp/json_rpc_client.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/README.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/README.md)
- [/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/protocols/openai_responses.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/protocols/openai_responses.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/mcp-ruby-sdk/examples/streamable_http_client.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/mcp-ruby-sdk/examples/streamable_http_client.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/mcp-ruby-sdk/lib/mcp/server/transports/streamable_http_transport.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/mcp-ruby-sdk/lib/mcp/server/transports/streamable_http_transport.rb)
