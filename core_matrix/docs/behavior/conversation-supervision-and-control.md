# Conversation Supervision And Control

## Purpose

`ConversationSupervision` is the durable conversation-scoped visibility and
operator-control surface for runtime work.

It answers two orthogonal questions:

- what the conversation is doing now
- how the previous work segment ended

It also powers:

- side chat replies built from frozen supervision snapshots
- short-lived current-or-previous-turn supervision feeds
- bounded conversation control requests with audit trails

## Canonical State

`ConversationSupervisionState` is the canonical read model.

Important fields:

- `overall_state`
  - answers what the conversation is doing now
  - supported values: `idle`, `queued`, `running`, `waiting`, `blocked`,
    `completed`, `failed`, `interrupted`, `canceled`
- `last_terminal_state`
  - answers how the previous work segment ended
  - supported values: `completed`, `failed`, `interrupted`, `canceled`
- `last_terminal_at`
  - timestamp for that previous terminal segment
- `board_lane`
  - supported values: `idle`, `queued`, `active`, `waiting`, `blocked`,
    `handoff`, `done`, `failed`

`idle` is not a synonym for success. It means there is no active turn, no
running workflow/task/subagent, and no waiting or blocked work, while the
conversation is still a live retained conversation.

Typical settled outcomes therefore project as:

- `overall_state = idle`, `last_terminal_state = completed`
- `overall_state = idle`, `last_terminal_state = failed`

The system should not keep reporting `overall_state = failed` once work has
already stopped and the conversation is merely idle.

## Feed And Snapshots

`ConversationSupervisionFeedEntry` is a short-lived, turn-scoped activity feed.
It is not an audit log.

- feeds are derived from explicit projector changes, not free-form callbacks
- feeds are scoped to the active turn, or the most recent turn when no newer
  turn has started yet
- human-visible summaries must not leak internal runtime vocabulary

`ConversationSupervisionSnapshot` freezes:

- canonical machine status
- compact context facts
- active plan items
- active child-task summaries
- capability and control authority state
- proof/debug refs kept out of human-visible side chat prose

`ConversationSupervisionSession` and `ConversationSupervisionMessage` remain an
ephemeral side-channel and must not mutate the target transcript.

## Side Chat

Side chat is a human interaction surface over frozen supervision snapshots.

- it reads `machine_status`, not raw workflow or mailbox payloads
- it can answer current work, recent progress, blockers, next steps, child-task
  state, and compact conversation facts
- human-visible text must not expose raw runtime tokens, numeric ids, or
  workflow-internal vocabulary
- proof/debug refs stay in the machine payload, not in the visible prose

## Control

Conversation control is conversation-scoped, bounded, and audited through
`ConversationControlRequest`.

Current bounded request kinds include:

- status refresh
- turn interrupt
- conversation close
- guidance to the active agent
- guidance to an active child task
- child-task close
- blocked-step retry
- waiting-workflow resume

Control is permitted only when:

- supervision is enabled
- side chat is enabled
- control is enabled
- the actor is the conversation owner or has an explicit capability grant

Side chat may classify a high-confidence imperative into one of those control
verbs, but ambiguous language stays ordinary chat.

## Acceptance Strategy

Two validation layers protect this surface:

- deterministic service and request tests for classification, projection, and
  dispatch behavior
- a provider-backed capstone acceptance matrix that exercises positive,
  negative, and ambiguous control utterances and exports a
  `control-intent-matrix.json` artifact when enabled
