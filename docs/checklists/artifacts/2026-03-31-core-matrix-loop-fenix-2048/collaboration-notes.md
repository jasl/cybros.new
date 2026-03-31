# Collaboration Notes

## Operator Notes

- The original stale-mailbox failure was fixed before this rerun by decoupling `execute_program_tool` timeout from the mailbox lease duration in `ProviderExecution::ProgramMailboxExchange`.
- This acceptance run validated that fix with a real long-running `npm install` inside Fenix: the tool call took minutes, but the terminal report still returned while the mailbox lease remained fresh.
- Host-side verification required one additional local `npm install` because the mounted workspace initially contained Linux optional native bindings produced inside the Docker runtime.

## Audit Outcome

- Fresh destructive reset completed before verification and acceptance.
- Full repository verification matrix passed before the 2048 run.
- No new runtime freshness or lease regressions were observed during the rerun.
