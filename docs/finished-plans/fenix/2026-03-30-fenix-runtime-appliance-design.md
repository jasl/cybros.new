# Fenix Runtime Appliance Design

## Status

- Date: 2026-03-30
- Status: approved draft, revalidated against the current validated runtime baseline
- Execution status: ready to execute from the current `agents/fenix` and `core_matrix` state; refresh again only if the mailbox/control or runtime-resource contracts change materially

## Goal

Turn `agents/fenix` from the current validated runtime baseline
into a default, distributable runtime appliance that:

- remains compatible with Core Matrix's `AgentProgramVersion + ExecutorProgram`
  model
- ships as the default agent implementation in Docker Compose deployments
- can also run bare-metal on Ubuntu 24.04 LTS with documented prerequisites
- keeps the path open for later splitting the agent plane from the execution
  environment plane
- treats most product capabilities as manifest/plugin-extensible instead of
  hardcoded Ruby constants

## Current Constraints

- `core_matrix` already models one stable `ExecutorProgram`, frozen
  `AgentProgramVersion` rows, and `program_plane` / `execution_plane` /
  `effective_tool_catalog` contracts.
- `agents/fenix` still exposes a mostly static pairing manifest and hardcoded
  tool composition, but it now handles both mailbox-driven agent execution and
  execution-plane process control over the shared control plane.
- `subagent_spawn`, `subagent_send`, `subagent_wait`, `subagent_close`, and
  `subagent_list` are Core Matrix reserved tools and should not be redefined as
  normal Fenix plugins.
- attached commands already use `exec_command` / `write_stdin` and the
  `CommandRun` contract; detached services already use `process_exec` and the
  `ProcessRun` contract.
- `agents/fenix` does not yet expose runtime foundation metadata, `.fenix`
  workspace bootstrap, plugin-registry-backed manifest composition, local web
  tooling, browser tooling, or fixed-port proxy support.
- Long-lived developer services should use the Core Matrix `ProcessRun` and
  `resource_close_*` contracts instead of pretending to be ordinary short-lived
  tool invocations.

## High-Level Decision

Build Fenix as a single Ubuntu 24.04-based runtime appliance first, but define
clear program-plane and execution-plane seams from the beginning.

The first release should keep one deployable service for product simplicity:

- one image
- one default Compose service
- one workdir mount
- one visible runtime identity

Internally, the implementation should still separate:

- program-plane logic
  - prompts
  - profiles
  - skills
  - context compaction
  - memory policy
  - plugin registry composition
- execution-plane logic
  - command execution
  - process management
  - browser automation
  - web fetch/search
  - workspace file surfaces
  - fixed-port development proxy

That split matches the Core Matrix domain model and keeps a later
`fenix-app + fenix-sandbox` decomposition feasible without redesigning the
product contract.

## Runtime Shape

The runtime appliance targets three deployment shapes:

1. Default: Docker Compose alongside Core Matrix
2. Advanced self-hosting: bare-metal Ubuntu 24.04 LTS
3. Development-only: macOS with best-effort support

The canonical shipped image should be based on `ubuntu:24.04` and include:

- Ruby and Bundler suitable for the Rails app and agent-side code execution
- Node.js LTS, npm, pnpm, and Playwright tooling
- Python plus `uv`
- Chromium for browser automation
- common shell/debugging utilities
- a reverse proxy suitable for fixed external developer access

The Dockerfile and bare-metal setup should share the same dependency model as
much as practical. A bootstrap script may be shared between Docker build steps
and documented Ubuntu host setup, but host automation is optional.

## Workspace Layout

The workspace root is a user-facing project directory mounted into the runtime,
for example `/workspace`.

Fenix-owned state lives under `/workspace/.fenix` to reduce accidental damage
to user project files and to keep runtime internals out of normal directory
listings.

Recommended layout:

```text
/workspace
  SOUL.md
  USER.md
  MEMORY.md
  .env
  .env.agent
  .fenix/
    memory/
      root.md
      daily/
        YYYY-MM-DD.md
    skills/
    plugins/
    conversations/
      <conversation_public_id>/
        meta.json
        MEMORY.md
        context/
          summary.md
          tool-state.json
        attachments/
        artifacts/
        runs/
```

Rules:

- `AGENTS.md` stays inside Fenix's code-owned prompt assets and is not seeded
  into the workspace.
- `SOUL.md`, `USER.md`, and `MEMORY.md` at the workspace root are optional user
  override files.
- Follow the OpenClaw bootstrap split: keep top-level prompt and curated-memory
  files small enough to inject every run, and keep bulk/diary-style notes in
  `.fenix/memory/daily/` rather than in the always-injected files.
- `.env` and `.env.agent` are optional overlays applied at:
  - workspace root
  - conversation directory
- Fenix should no longer model lane-local workspace state. Child work happens in
  child conversations.
- Conversation directories are keyed by `conversation_public_id`, not by a root
  conversation path tree.
- `meta.json` may cache runtime-facing metadata such as:
  - `conversation_public_id`
  - `parent_conversation_public_id`
  - `root_conversation_public_id`
  - `subagent_session_public_id`
  - `depth`
  - `addressability`

This metadata is a Fenix runtime convenience layer. It does not require new
Core Matrix columns in the first phase.

## Prompt And Memory Assembly

Prompt assembly order should be:

1. built-in Fenix `AGENT` prompt
2. built-in default `SOUL`
3. built-in default `USER`
4. workspace override files when present
5. conversation scope summary and memory material

Memory management should remain visible on disk, not only in SQL or transient
context payloads.

The memory policy should follow the OpenClaw shape closely:

- workspace-root `SOUL.md`, `USER.md`, and curated `MEMORY.md` are bootstrap
  overlays and should stay concise
- daily/raw notes belong under `.fenix/memory/daily/YYYY-MM-DD.md`
- daily memory files are not auto-injected every turn; they are read on demand
  by memory tools or compaction/summarization flows
- subagent/minimal prompt modes should use a narrower injected subset than the
  main conversation path so child runs do not inherit the full memory payload

Minimum scopes:

- root/workspace scope
- conversation scope

When context pressure requires compaction, Fenix should write durable summaries
back into `.fenix/conversations/<id>/context/summary.md` and the relevant memory
files instead of keeping them only inside runtime payloads.

## Tool Boundary

### Core Matrix reserved tools

These are not normal Fenix plugins:

- `subagent_spawn`
- `subagent_send`
- `subagent_wait`
- `subagent_close`
- `subagent_list`
- any `core_matrix__*` tool

Fenix should consume their visibility and policy through the runtime capability
contract, not redefine them.

### Fenix built-in core hooks

These remain code-owned:

- `compact_context`
- `estimate_messages`
- `estimate_tokens`

They are part of Fenix's identity and orchestration loop.

### Fenix environment/product plugins

Everything else should move behind a plugin registry and manifest composition
model:

- `exec_command`
- `write_stdin`
- workspace tools
- memory tools
- `web_fetch`
- `web_search`
- Firecrawl-specific tools
- browser and Playwright tools
- dev-proxy tools

## Plugin Model

The first implementation should stop treating the tool catalog as one static
Ruby constant and instead compose it from a registry.

Suggested plugin roots:

- code-owned system plugin manifests under `app/services/fenix/plugins/system`
- code-owned curated plugin manifests under `app/services/fenix/plugins/curated`
- live workspace plugins under `/workspace/.fenix/plugins`

Suggested manifest shape:

- `plugin_id`
- `version`
- `display_name`
- `default_runtime_plane`
- `tool_catalog`
- `config_schema`
- `requirements`
- `env_contract`
- optional `healthcheck`
- optional `bootstrap`
- optional future slot metadata or runtime hints

The manifest schema should be intentionally wider than the first runtime cut.
If a field is not needed yet, Fenix may accept and retain it while treating the
corresponding implementation surface as a no-op or stub. The first cut can
support only built-in Ruby-backed plugins plus configuration driven provider
adapters. It does not need to execute arbitrary third-party Ruby code from the
workspace on day one.

## Command And Process Model

The execution model should follow the separation already visible in Core Matrix
and in Codex:

### Attached command tools

Use pluggable command tools with Codex-like naming:

- `exec_command`
- `write_stdin`

Behavior:

- optional PTY support
- streamed stdout/stderr
- attached command semantics
- terminal result belongs to one `ToolInvocation`
- timeout/local terminate is handled inside the tool runtime

The current baseline already exposes these names and resource contracts. The
appliance work should preserve the external tool names while moving the
implementation behind plugin-registry-backed composition.

### Long-lived process tools

Do not overload `exec_command` for services such as Vite, Rails dev server,
Next.js, preview servers, file watchers, or tunnel-like helpers.

Those should map to Core Matrix `ProcessRun` semantics through a distinct tool
family, for example:

- `process_exec`
- or product-specific tools such as `dev_server_start`

Behavior:

- output flows through `runtime.process_run.output`
- close flows through `resource_close_request` and terminal close reports
- route registration can attach to the fixed-port dev proxy

## Web And Browser Strategy

### `web_fetch`

Default implementation is local and should include:

- `http/https` only
- SSRF/private-address blocking
- redirect re-checking
- text/markdown extraction
- output limits
- caching

If Firecrawl is configured, `web_fetch` may fall back to Firecrawl scrape for
hard pages.

### `web_search`

First priority provider is Firecrawl.

The runtime should support both:

- generic `web_search` with configurable provider = `firecrawl`
- explicit provider tools:
  - `firecrawl_search`
  - `firecrawl_scrape`

That matches the OpenClaw pattern and lets generic reasoning flows and
power-user Firecrawl-specific flows coexist.

### Browser / Playwright

Chromium and Playwright should be bundled into the runtime appliance and exposed
through a dedicated browser/plugin surface instead of hiding browser automation
behind `web_fetch`.

## Fixed-Port Dev Proxy

Fenix should provide a stable external entrypoint for services started inside the
runtime.

Recommendation:

- use a dedicated reverse proxy, preferably Caddy
- expose one fixed external port
- route process-backed services by a stable path prefix such as
  `/dev/<resource_id>/...`

This keeps external access simple while allowing the underlying processes to
bind random or internal ports.

The proxy should integrate with long-lived process tools rather than attached
command tools.

## Delivery Phases

### Stage 1: Runtime foundation

- Ubuntu 24.04 image
- toolchain installation
- workspace `.fenix` bootstrap
- plugin registry skeleton
- bare-metal requirements documentation

### Stage 2: Core pluggable tools

- `exec_command`
- `write_stdin`
- workspace tools
- memory tools
- manifest composition from plugin registry

### Stage 3: Web and browser

- local `web_fetch`
- Firecrawl-backed `web_search`
- explicit Firecrawl tools
- browser and Playwright tooling

### Stage 4: Long-lived processes and proxy

- `ProcessRun`-backed long-lived process tools
- fixed-port dev proxy
- routing and close integration
- Compose-first distribution polish

## Revalidation Checklist Before Implementation

Before any implementation starts, re-check:

- the latest `agents/fenix` manifest and execution runtime shape
- the latest `core_matrix` process and close-report contracts
- the final committed state of streamed command execution work
- whether any ongoing refactors already introduced:
  - plugin registry helpers
  - execution-plane execution paths
  - workspace bootstrap code
  - process-backed tool abstractions

If any of those changed materially, regenerate the implementation plan before
writing production code.
