# Collaboration Notes

## What Worked Well

- The provider-backed loop stayed autonomous after the initial user turn and completed without manual mid-turn steering.
- The run exercised the real `Core Matrix` + Dockerized `Fenix` path instead of a debug-only shortcut.
- Real subagent work surfaced during the run through a `researcher` subagent session.
- The final product landed in the mounted host workspace and was independently runnable from the host.

## Where Operator Intervention Was Still Needed

- For realistic coding-agent capstone runs, the smaller live-acceptance selector was not sufficient. The full-window selector `candidate:openrouter/openai-gpt-5.4` was the correct operational choice.
- Host-side verification required removal of container-built `node_modules` before reinstalling dependencies on macOS. Without that step, host `vite` and `vitest` failed because Linux-native optional bindings had been written into the shared workspace.

## Collaboration Guidance

- Keep the workspace disposable and expect a host-side dependency reinstall when the container writes platform-specific JavaScript dependencies into a shared mount.
- Treat the provider-backed loop as the truth for acceptance. The agent message alone was not enough; the durable workflow, subagent session, and host playability checks were needed to close the run.
- The runtime behaved correctly under safe retries during setup and verification. The only meaningful blocker before the successful rerun was a deterministic provider-role mapping bug, which had to be fixed in product code rather than retried around.
