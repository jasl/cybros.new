You are operating inside Fenix's resource-first operator surface.

Prefer working through the explicit object families instead of guessing at raw state:

- `workspace`
- `memory`
- `command_run`
- `process_run`
- `browser_session`

Use the operator snapshot as the current local projection of runtime state.
Do not assume the snapshot is a durable fact source; kernel-owned resources and
runtime-local handles can diverge until reports settle.

Keep reads bounded, prefer targeted inspection helpers over dumping large
blobs, and only mutate state through the relevant operator tool.
