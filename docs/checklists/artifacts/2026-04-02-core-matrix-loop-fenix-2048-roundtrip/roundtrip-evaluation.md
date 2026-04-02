# Conversation Export / Import / Debug Evaluation

## User export roundtrip

Original conversation: `019d4e6e-7ab3-7dd2-9d06-4b11cc59e729`
Imported conversation: `019d4e75-1ffb-72f5-9fa3-3e575b690824`

Results:
- `ConversationExport` succeeded through `/app_api/conversation_export_requests`.
- The exported user zip contains `manifest.json`, `conversation.json`, `transcript.md`, and `conversation.html`.
- `ConversationImport` succeeded through `/app_api/conversation_bundle_import_requests`.
- Transcript comparison is exact for user-visible content: `same_content = true`.

## Debug export usefulness

The debug bundle is sufficient to assess:
- which provider/model actually ran: `openrouter` / `openai-gpt-5.4`
- total round count: `39`
- total input/output tokens: `832909` / `11782`
- total tool-call count: `39`
- high-level tool mix, including reads, writes, command execution requests, browser open/content, and process execution requests
- final assistant claim and final browser content
- detailed workflow/node/event timeline

The debug bundle was also sufficient to catch an invalid acceptance run earlier in the session that accidentally used `candidate:dev/mock-model`.

## Current limitations

The debug bundle is not yet sufficient for strongest-possible verification of internal execution semantics because:
- `command_runs.json` is empty even though `tool_invocations.json` includes `exec_command` calls and returns runtime `command_run_id` values.
- `process_runs.json` is empty even though the tool breakdown reports one `process_exec` call.
- `subagent_sessions.json` is empty for this run, which is fine for this specific conversation but means delegation proof still depends on whether the run actually delegated.
- `estimated_cost_total` remains unavailable because provider-side cost data is not populated; token/latency accounting is still correct.

Conclusion:
- For internal review, the debug bundle is already good enough to judge provider choice, token usage, loop heaviness, tool strategy, and whether the conversation looks plausibly real.
- It is not yet good enough to treat command/process execution and subagent activity as fully auditable first-class evidence.
