# Agent Progress And Plan Items

## Purpose

Agent and child-task progress is published as normalized runtime facts and then
projected into conversation supervision.

The goal is to keep operator-facing state stable even when provider rounds,
workflow nodes, and tool calls change internally.

## Agent Task Progress

`AgentTaskRun` stores normalized supervision facts such as:

- `supervision_state`
- `focus_kind`
- `request_summary`
- `current_focus_summary`
- `recent_progress_summary`
- `waiting_summary`
- `blocked_summary`
- `next_step_hint`
- `last_progress_at`

Structured plan and progress rows live beside that state:

- `TurnTodoPlan`
  - one active plan head per task
  - captures goal summary, current item key, and status counts
- `TurnTodoPlanItem`
  - explicit item key, title, kind, status, and order
  - may reference a delegated child task when relevant
- `AgentTaskProgressEntry`
  - explicit progress sequence, kind, summary, and timestamp

Those rows are operator-facing inputs. They should not be reconstructed later
from runtime-private tokens.

## Child Task Progress

`SubagentSession` mirrors the same normalized supervision shape for delegated
work:

- `observed_status`
- `supervision_state`
- `request_summary`
- `current_focus_summary`
- `recent_progress_summary`
- `waiting_summary`
- `blocked_summary`
- `next_step_hint`
- `last_progress_at`

This lets conversation supervision talk about active child tasks without
re-parsing child workflow internals.

## Projection Into Conversation Supervision

`Conversations::UpdateSupervisionState` folds those runtime facts into one
conversation-level read model.

Important derived projections:

- active plan-item counts and badge strings
- active child-task counts and summaries
- waiting and blocked summaries
- last terminal state and time
- board-lane classification

When active work disappears, the projector must fall back to `idle` and keep
the previous terminal outcome in `last_terminal_state` and `last_terminal_at`.

## Side Chat And Feed Expectations

Side chat and the supervision feed consume the projected state above; they do
not re-derive operator language from raw workflow event names.

Human-visible content should therefore be written from:

- normalized progress fields
- explicit turn todo plan views
- explicit child-task summaries
- feed summaries that already passed internal-token filtering
