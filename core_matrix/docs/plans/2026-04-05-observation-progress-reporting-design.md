# Observation Progress Reporting Design

## Goal

Make `ObservationConversation` report workflow progress in user-facing natural
language so a human can understand what the agent has done, what it is doing,
and, when justified by evidence, what it will do next.

The human-visible response must not leak internal workflow structure such as
`provider_round_*`, `tool_*`, `runtime.workflow_node.*`, or internal wait
reason tokens.

## Problem

The current observation responder builds human-facing text by humanizing
internal status tokens. That keeps public ids out of the response, but it still
surfaces internal orchestration details that ordinary users should never need
to understand.

Today the artifacts can contain language such as:

- `Running provider round 6 tool 1 (running)`
- `runtime.workflow_node.completed event`
- `subagent_barrier`

Those phrases are operationally accurate, but they fail the product goal.
Humans need progress updates framed around their request and the work being
performed, not around Core Matrix or Fenix runtime internals.

## Desired Outcome

For observation questions such as "what are you doing right now?" or "what
changed most recently?", the response should sound like an agent progress
report:

- "I am working on the observation reporting change for this request."
- "I just finished checking the current implementation and moved on to the next
  change."
- "I am waiting on a helper task to finish before I continue."
- "Next I will run the relevant verification for this change."

If the snapshot does not justify a "next step" statement, the response should
omit it instead of guessing.

## Design Principles

### 1. Separate audit facts from human narration

`assessment` and `supervisor_status` remain the audit-oriented structures. They
may continue to carry internal ids, event kinds, and proof refs because they
exist for evidence and debugging.

Human-visible text must be produced from a separate user-facing semantic layer.

### 2. Freeze user-facing semantics in the observation snapshot

The observation frame already freezes a bounded bundle snapshot. The same
snapshot should also freeze a compact semantic view of the work so the human
response is stable across later conversation changes.

### 3. Store summaries, not raw transcript text

The new semantic layer may derive short summaries from the current turn input
and execution state, but it must not retain raw transcript text or quote prior
messages verbatim.

### 4. Never humanize internal tokens directly

Converting `provider_round_6_tool_1` into `provider round 6 tool 1` is still a
leak. The human responder must classify internal state into user-facing work
categories such as research, implementation, testing, waiting, completion, and
failure.

### 5. Next-step reporting is evidence-gated

The responder may report the next step only when:

- the snapshot contains an explicit semantic hint, or
- the next step can be conservatively inferred from the latest user-facing
  progress summary

Otherwise the response should simply omit a next-step sentence.

### 6. Subagent reporting should summarize purpose, not transport state

When subagents are active, the human response should summarize their purpose or
impact on the mainline work, not expose session ids or low-level status tokens.

## Reference Findings

The user explicitly asked whether repository references contained useful prior
art.

### OpenCode

`references/original/references/opencode/packages/web/src/content/docs/plugins.mdx`
contains a continuation/compaction prompt shape that asks for:

- the current task and its status
- which files are being modified and by whom
- blockers or dependencies between agents
- the next steps to complete the work

That structure is directly relevant. It reinforces that progress reporting
should be organized around task, status, blockers, and next steps rather than
runtime implementation details.

### Claude Code restored source

The restored Claude sources show explicit support for subagent progress
summaries and worker status aggregation rather than exposing raw child events.
That is relevant as a design direction: summarize subordinate work in a
human-readable way instead of exposing internal agent transport state.

### Codex reference

The inspected Codex reference did not surface a directly reusable supervisor or
observation progress prompt. It was not a strong source for this particular
feature.

## Proposed Architecture

### Keep the existing machine-facing layers

No product-facing behavior should depend on removing or weakening:

- `EmbeddedAgents::ConversationObservation::BuildAssessment`
- `EmbeddedAgents::ConversationObservation::BuildSupervisorStatus`

These continue to own:

- overall state
- current activity
- blocking reason
- recent activity items
- proof refs

### Add a new frozen `work_context_view`

`EmbeddedAgents::ConversationObservation::BuildBundleSnapshot` should append a
new top-level payload:

- `work_context_view`

This payload is user-facing semantic context and should contain only compact,
derived summaries. Suggested fields:

- `request_summary`
- `current_focus_summary`
- `recent_progress_summary`
- `waiting_summary`
- `next_step_hint`
- `subagent_summary`
- `work_type`

Each field is optional. Missing information should remain absent rather than
filled with synthetic placeholders.

### Add a semantic builder

Introduce a service dedicated to deriving `work_context_view` from the frozen
observation sources available at frame creation time. It should inspect:

- current turn input message content
- workflow run lifecycle and wait state
- workflow node key/type only as classification hints
- recent runtime activity kinds only as classification hints
- active subagent records

The service must never copy raw transcript text into the snapshot output.

### Add a progress narrator

Replace the current "humanize internal status" approach in
`BuildHumanSidechat` with a narrator that composes sentences from
`work_context_view`.

The narrator should answer observation questions in this order:

1. what I am doing now
2. what changed most recently, if supported by evidence
3. why I am waiting, if the user asked and the snapshot justifies it
4. what happens next, only when evidence supports it
5. grounding sentence

## Semantic Derivation Rules

### Request summary

Derive a short user-facing summary from the selected input message of the
current turn.

Examples:

- "fix the observation progress update"
- "complete the 2048 acceptance coverage"
- "investigate the current implementation"

This is a summary, not a quote.

### Work type classification

Classify current work into one of a small number of human categories:

- `research`
- `implementation`
- `testing`
- `waiting`
- `completed`
- `failed`
- `general`

Classification may use node keys, wait state, and recent runtime activity as
hints, but those hints must not be emitted directly.

### Current focus summary

Describe the current work in terms of the request and work type.

Examples:

- "I am updating the implementation for this request."
- "I am checking the current behavior before changing it."
- "I am running verification for the change."
- "I am waiting for a helper task to finish before continuing."

### Recent progress summary

Describe the most recent durable progress in user-facing language. This should
prefer semantic milestones such as:

- review completed
- code change completed
- verification started or completed
- helper result arrived
- work moved into a waiting state

It must not output raw event kinds.

### Waiting summary

Translate wait reasons into user language.

Examples:

- `subagent_barrier` -> "I am waiting for a helper task to finish before I can continue."
- `human_interaction` -> "I am waiting for input before I can continue."
- unknown wait reason -> "I am waiting on a dependency before I can continue."

### Next-step hint

Populate only when the snapshot justifies it.

Good examples:

- after a review-like progress summary: "Next I will apply the change."
- after implementation progress with no terminal state: "Next I will run the relevant checks."
- while waiting on a helper task: "Once that result is back, I will continue the main task."

Bad examples:

- any fabricated step not supported by the snapshot
- repeating internal workflow transitions as next steps

## Human Response Rules

### "What are you doing right now?"

Return the current focus summary first. If available, append a short recent
progress sentence.

### "What changed most recently?"

Return the recent progress summary. If the snapshot only proves that progress
occurred but not the user-facing semantic, say so in plain language without
using internal event names.

### "Why are you waiting?"

Use `waiting_summary`. Never emit raw wait reason tokens.

### "What are subagents doing?"

Use `subagent_summary`. Speak about purpose or role, not session ids or raw
status tokens.

### Default summary path

`BuildHumanSummary` should use the same semantic layer so fallback summaries
also avoid internal token leakage.

## Acceptance and Test Changes

### Core Matrix tests

Add or update tests so human-facing content explicitly rejects internal token
leaks, including:

- `provider_round`
- `tool_`
- `runtime.`
- `subagent_barrier`
- raw snake_case wait or event tokens

Also add positive assertions for user-facing wording around:

- current work
- recent progress
- waiting reason
- next step when supported

### Acceptance leak scan

The current acceptance leak scan only catches long numeric tokens and UUIDs.
That is too weak for this feature.

Expand the scan so `observation-conversation.md` fails when human-visible text
contains internal workflow vocabulary such as:

- `provider_round_*`
- `tool_*`
- `runtime.*`
- known internal wait reason tokens
- other Core Matrix internal workflow identifiers

This ensures the acceptance test protects the actual product requirement rather
than only public-id boundaries.

## Risks

### Over-inference

If the semantic builder infers too much from sparse evidence, the response may
sound plausible but inaccurate. The design mitigates this by allowing omission
of unsupported "next step" claims.

### Weak summaries from sparse snapshots

The current frozen bundle is intentionally compact. If it remains too sparse,
the product may need an additional summary field derived at frame creation time
from the current turn input.

### Regression back to internal token output

Without explicit tests and acceptance leak checks, future changes could easily
reintroduce humanized internal node keys. The new tests must lock this down.

## Recommended Implementation Direction

1. Add `work_context_view` to the frozen bundle snapshot.
2. Derive user-facing semantic summaries at frame creation time.
3. Refactor `BuildHumanSidechat` and `BuildHumanSummary` to narrate from those
   summaries instead of internal tokens.
4. Strengthen unit tests and the 2048 acceptance leak scan so internal runtime
   structure cannot leak back into human-visible observation replies.
