# Conversation Observation And Supervisor Status

## Migration Note

This document is now a migration note.

`ConversationObservation*` is no longer the living runtime contract. The
supervision refactor replaced that domain with `ConversationSupervision*` and
split the source of truth across:

- [`conversation-supervision-and-control.md`](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/conversation-supervision-and-control.md)
- [`agent-progress-and-plan-items.md`](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-progress-and-plan-items.md)

Use those documents for:

- canonical conversation supervision state
- short-lived supervision feed behavior
- side chat rendering
- bounded conversation control
- runtime progress facts and plan-item projection

`observation` remains only as a historical migration term. New product,
service, controller, acceptance, and artifact work should use supervision
naming directly.
