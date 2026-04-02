# Debug Evaluation

- Source conversation: `019d4ea9-7297-7426-aa1a-a371b8e512cb`
- Imported conversation: `019d4eae-1568-721b-a588-67d8b45ae378`
- Transcript roundtrip match: `true`
- Command runs exported: `3`
- Process runs exported: `1`
- Usage events exported: `13`
- Input tokens: `59092`
- Output tokens: `924`

## Notes

- The debug bundle now includes durable `command_runs.json` and `process_runs.json` entries for the real successful provider-backed run.
- The source conversation diagnostics were materialized through `ConversationDiagnostics::RecomputeConversationSnapshot` and embedded into the debug bundle.
- The imported conversation was created as a new conversation and its transcript matches the source transcript exactly at the exported role/slot/content level.
