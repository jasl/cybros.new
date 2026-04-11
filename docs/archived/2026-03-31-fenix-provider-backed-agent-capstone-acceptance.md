# Fenix Provider-Backed Agent Capstone Acceptance Checklist

## Status

Living checklist for the first real end-to-end acceptance of the
provider-backed `Fenix` coding-agent product line.

This checklist supersedes simulated "manual operator" close-out as the final
acceptance standard for this line of work. Local protocol proofs, smoke tests,
and deterministic runtime checks remain useful, but they do not close the work
unless this capstone workload also passes.

## Purpose

The goal is to prove that the product is not merely a runtime substrate. It
must behave like a real coding agent that can:

- receive a real user task through the normal conversation and turn model
- decide how to use its built-in planning and optional app-local capabilities
- use tools through a provider-backed agent loop
- spawn and coordinate subagents when appropriate
- edit a real workspace and run a real development server
- produce a browser application that a human can actually play

For this capstone, `Core Matrix` and `Fenix` are treated as fully orthogonal
and fully complementary:

- `Core Matrix` owns the provider-backed loop, tool calling substrate, generic
  MCP support, workflow orchestration, and durable proof
- `Fenix` owns prompt preparation, skills policy, and execution of
  agent-owned tools through the published runtime contract

## Fixed Acceptance Workload

The capstone task is fixed:

- deploy a complete `Core Matrix` plus `Fenix` stack
- run `Fenix` in Docker
- build the Docker runtime on top of `images/nexus`
- mount `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix` as the runtime
  workspace
- through a real conversation and turn sequence, have `Fenix` build a
  browser-based React `2048` game

For multi-turn provider-backed capstone runs, prefer a full-window selector
such as `candidate:openrouter/openai-gpt-5.4`. The
`openai-gpt-5.4-live-acceptance` profile remains useful for short smoke
validation, but it is intentionally too small for a realistic coding-agent
capstone once prompt sections, tool surface, and turn history accumulate.

The final application must be runnable from the host machine using the mounted
workspace contents in `tmp/fenix`.

The current runtime contract baseline for this acceptance is
`agent-runtime/2026-04-01`. Manual validation, proof capture, and any helper
scripts used during the run must read the sectioned envelope shape:

- `task`
- `conversation_projection`
- `capability_projection`
- `provider_context`
- `runtime_context`
- `task_payload`

After the provider-backed turn completes, the capstone close-out must use the
product-facing `app_api` surfaces for conversation review and bundle
portability:

- `ConversationDiagnostics` through `/app_api/conversation_diagnostics/*`
- `ConversationExport` through `/app_api/conversation_export_requests`
- `ConversationDebugExport` through `/app_api/conversation_debug_export_requests`
- `ConversationImport` through `/app_api/conversation_bundle_import_requests`

## Hard Requirements

### Runtime Shape

- `Core Matrix` may run by any normal local operator method
- `Fenix` must run in Docker, not in-process on the host
- before each capstone run, perform a fresh start of the host services and the
  Dockerized runtime stack; the default external harness entrypoints are:
  - `/Users/jasl/Workspaces/Ruby/cybros/acceptance/bin/fresh_start_stack.sh`
  - `/Users/jasl/Workspaces/Ruby/cybros/acceptance/bin/run_with_fresh_start.sh`
- the dedicated Fenix capstone entrypoint is
  `/Users/jasl/Workspaces/Ruby/cybros/acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh`
- in Docker mode, rebuild the runtime image from the current
  `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix` source tree on top of the
  current `/Users/jasl/Workspaces/Ruby/cybros/images/nexus` base before
  starting the containers; do not live-sync repo files into a running runtime
  container
- if a validation script expects a runtime on a non-default port, pass the
  same `FENIX_RUNTIME_BASE_URL` into the wrapper so the fresh-start gate boots
  the correct endpoint first
- the Docker container must mount the workspace to
  `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix`
- the development server must be reachable from the host machine
- after external registration returns the runtime connection credential, start the
  persistent runtime worker inside the Docker container with the same
  `CORE_MATRIX_BASE_URL`, `CORE_MATRIX_MACHINE_CREDENTIAL`, and execution
  credential
- the runtime worker must include both the mailbox control loop and active
  queue processing, for example via `bin/runtime-worker` with Puma's embedded
  Solid Queue supervisor or another equivalent runtime-specific arrangement
- only one runtime-worker / Solid Queue worker set may run for a given
  Dockerized `Fenix` runtime at a time; registry-backed browser, command, and
  process handles are runtime-local in-memory state and do not survive
  duplicate worker pools

### Agent Behavior

- the work must run through the real conversation and turn model
- `Core Matrix` must execute the repeated provider-backed loop
- `Fenix` must provide prompt preparation and agent-owned tool execution
  through the published runtime endpoints
- the run must use the sectioned runtime contract above; no legacy flat
  `agent_context`, `context_messages`, or `program_tools` payloads may be used
- the work must use the real tool surface rather than offline file injection
- the work must rely on native runtime behavior rather than staged workflow
  bootstrap skills
- the work must be eligible to use app-local skills and subagents when the
  product chooses that path
- the run must leave proof that subagent work actually happened when the agent
  chooses that path

### Output Product

- the final application must be a playable `2048` game
- the game must be implemented in a browser-based React stack
- the host machine must be able to inspect the final source tree in
  `tmp/fenix`
- the host machine must be able to serve and inspect the runtime-generated
  `dist/` artifact from that workspace for playability verification

## Per-Turn Recording Requirements

For every turn in the capstone run, record:

- scenario date and operator
- conversation `public_id`
- turn `public_id`
- workflow-run `public_id`
- agent agent snapshot identifier, execution runtime identifier, and runtime mode
- provider handle, model ref, and API model when applicable
- expected DAG shape
- observed DAG shape
- expected conversation state
- observed conversation state
- whether subagent work was expected on that turn
- whether subagent work was observed on that turn
- proof artifact path, when applicable
- pass, fail, or blocked outcome

Only `public_id` values may appear in operator-facing records. Do not record
internal numeric ids.

## Required Proof Package

Every capstone run must produce a proof package containing at least:

- `turns.md`
  - per-turn `public_id`, DAG shape, state, and outcome summary
- `conversation-transcript.md`
  - the real user and agent chat transcript for the run
- `collaboration-notes.md`
  - short notes explaining what worked well, where the agent needed steering,
    and how a human can collaborate with it more effectively
- `runtime-and-bindings.md`
  - how `Core Matrix` and Dockerized `Fenix` were started
  - must explicitly record how the runtime worker and queue worker were started
    after registration
- `workspace-artifacts.md`
  - final source-tree location, `dist/` artifact location, start command, and run URL
- `playability-verification.md`
  - actual play verification notes
- `export-roundtrip.md`
  - user export, debug export, and import roundtrip outcome
  - must record whether the imported transcript matches the source transcript
  - must record whether the debug bundle was sufficient to assess provider,
    model, token usage, round count, tool mix, and durable runtime resources
- `agent-evaluation.md`
  - structured acceptance review for result quality, runtime health,
  convergence, and cost efficiency
  - must cite the concrete proof inputs used for each conclusion
  - must make it explicit when a run functionally passes but still shows weak
  convergence or poor efficiency

Store the generated package under
`/Users/jasl/Workspaces/Ruby/cybros/acceptance/artifacts/<run-stamp>/`. These
artifacts are runtime output, not committed repository content.

Optional but recommended artifacts:

- `agent-evaluation.json`
  - machine-readable form of the structured acceptance review
- browser screenshots
- screen recording clips
- exported workflow proof graphs
- selected command or tool transcripts

## Playability Verification

The final page must be verified as playable, not merely visible.

Minimum manual verification:

- start the exported `dist/` artifact from the host machine using the
  generated workspace
- open the game in a browser
- play at least one real session with keyboard input
- verify tile movement in all applicable directions
- verify merge behavior for equal adjacent tiles
- verify a new tile appears after each valid move
- verify score changes when merges occur
- verify game-over behavior
- verify restart or new-game behavior

Verification notes:

- use browser session tools or a host-side browser for local playability
  checks; `web_fetch` is not an acceptable substitute for loopback or other
  private development URLs because those destinations are intentionally
  blocked by the web tool runtime
- host-side `dist/` serving is the primary portability check for this
  benchmark because it validates the platform-independent output that an end
  user actually consumes
- if the mounted workspace contains container-built `node_modules` or other
  platform-specific dependency artifacts, the operator may remove and
  reinstall those dependencies on the host before source-portability
  diagnostics; the proof package must record that step
- host-side `npm test` and `npm run build` are source-portability diagnostics,
  not by themselves the primary benchmark gate
- platform-specific dependency rebuilds on the host are an operational
  verification concern, not by themselves an agent-quality failure; do not
  fail the capstone solely because Docker-built `node_modules` cannot run on
  macOS if the conversation/runtime proof and host-served `dist/` artifact
  still establish a playable result

Recommended stronger verification:

- record a short deterministic move sequence and compare the resulting board
  state against expected behavior
- attach screenshots or a short screen recording of live play

The page does not pass if it is only a static mockup or if the rules are
visibly incorrect.

## Subagent Verification

The acceptance run must look for real subagent work rather than assuming a
single-agent path.

Subagent evidence may include:

- workflow nodes or reports that correspond to subagent work
- turn-level DAG shapes that show subagent-related structure
- transcript evidence that the agent deliberately delegated a bounded task
- produced artifacts whose provenance clearly comes from subagent execution

The run does not fail merely because a specific turn stayed single-agent, but
the overall capstone run should demonstrate that the system can surface real
subagent work under a task complex enough to justify it.

## Acceptance Review Rubric

In addition to pass or fail, every capstone proof package must include a
structured review of the completed run. This review exists to prevent
acceptance from collapsing into a binary "it worked" judgment when the debug
bundle already contains enough evidence to assess how the agent worked.

The acceptance review must score and explain all of the following dimensions:

- `result_quality`
  - whether the produced application actually satisfies the benchmark outcome
  - must consider game correctness, conversation/runtime-side test and build
    results, host-served browser playability, export/import transcript
    roundtrip integrity, and any host-side portability diagnostics
- `runtime_health`
  - whether the system completed without relying on unstable runtime behavior
  - must consider provider success rate, retry or resume churn, tool and
    runtime resource failure rate, and whether durable command or process
    evidence remained inspectable through the debug bundle
- `convergence`
  - whether the agent reduced uncertainty quickly instead of repeatedly
    re-reading context and re-running the same validations
  - must consider provider round count, repeated command patterns, repeated
    test/build/preview churn, and whether subagent work reduced or merely
    expanded the search path
- `cost_efficiency`
  - whether the cost of the run was proportional to the task difficulty and
    final result quality
  - must consider input and output token totals, tool-call count, command and
    process churn, and whether repeated verification produced materially new
    information

For this fixed `2048` benchmark, the review must be grounded in the exported
proof, especially:

- `run-summary.json`
- `diagnostics.json`
- `tool_invocations.json`
- `command_runs.json`
- `process_runs.json`
- host-side portability outputs such as `npm test`, `npm run build`, and
  browser playability notes against the exported `dist/` artifact

The review should use a small explicit scale such as:

- `strong`
- `acceptable`
- `weak`

or, when a hard gate fails:

- `fail`

The exact labels may vary, but the review must clearly distinguish:

- functional success from agent quality
- runtime correctness from agent convergence
- acceptable cost from poor efficiency

A run may therefore pass the benchmark while still receiving a weak
`convergence` or poor `cost_efficiency` assessment. That is not a checklist
contradiction; it is the point of the structured review.

## Pass Criteria

The capstone run passes only if all of the following are true:

- the stack deploys successfully with Dockerized `Fenix`
- `Fenix` completes the workload through the real conversation and turn path
- per-turn DAG and conversation-state records are complete
- the final application is present under `tmp/fenix`
- runtime-generated memory, prompts, and conversation-local artifacts may live
  under the agent-snapshot namespace inside
  `tmp/fenix/.fenix/agent_snapshots/...`
- the game is actually playable by a human
- the proof package is complete, including chat transcript and collaboration
  notes
- the user export, debug export, and import roundtrip succeeds through the
  `app_api` surfaces
- the imported conversation preserves the source transcript at the user-visible
  role/slot/content level
- the debug export is sufficient to assess provider/model choice, token usage,
  round count, tool mix, and durable command/process resource evidence

If any one of these fails, the capstone acceptance remains open.

## Blocking Failure Examples

Any of the following is a blocking failure:

- the workload only succeeds through deterministic test modes
- the stack requires bypassing the normal conversation and turn flow
- subagent capability is only advertised in metadata but never executable
- the final application is a static UI without working `2048` rules
- the source does not land in the mounted host workspace
- per-turn proof cannot explain the observed DAG or conversation state

## Execution Notes

- use the same real-environment discipline as prior manual acceptance work:
  shell commands, HTTP requests, Docker operations, Rails runners, and browser
  interaction
- keep the capstone workspace disposable so the full run can be repeated
- prefer reusing shared manual-acceptance helpers where possible, but the run
  must exercise the real product path rather than a special debug entrypoint

## Related Documents

- [2026-03-24-core-matrix-kernel-manual-validation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md)
- [2026-03-31-fenix-operator-surface.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/2026-03-31-fenix-operator-surface.md)
- [2026-03-30-fenix-runtime-appliance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/2026-03-30-fenix-runtime-appliance.md)
