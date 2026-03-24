# Core Matrix Phase 2 Agent Loop Execution Follow-Up

## Status

Deferred future plan. This is the next intended phase after the current
substrate batch completes.

## Purpose

Phase 2 proves that Core Matrix can run a real agent loop end to end under
kernel authority.

## Success Criteria

- a real turn enters the kernel and reaches terminal or waiting state through a
  real execution path
- real provider execution works under workflow control
- tool invocation works through unified capability governance
- at least one subagent path works in a real run
- at least one human-interaction path works in a real run
- drift, outage, and recovery semantics are validated in a real run
- the phase passes automated tests plus real-environment manual validation under
  `bin/dev` with a real LLM API

## Core Matrix Work

- build the real loop executor
- complete unified capability governance for provider, MCP, and agent-program
  tool execution
- formalize override, whitelist, and reserved-prefix rules
- formalize conversation feature policy and freeze feature snapshots on running
  execution
- record invocation attempts, failures, retries, waits, and recovery outcomes

## Fenix Validation Slice

`agents/fenix` is the default validation program for this phase.

It should prove:

- general-assistant conversation flows
- coding-assistant flows
- everyday office-assistance flows
- real tool use
- real subagent behavior
- human-interaction and recovery paths

## Out Of Scope

- Web UI productization
- workspace-owned trigger infrastructure
- IM, PWA, or desktop channels
- extension and plugin packaging
