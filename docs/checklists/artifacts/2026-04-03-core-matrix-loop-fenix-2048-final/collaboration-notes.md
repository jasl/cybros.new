# Collaboration Notes

## What Worked Well

- The provider-backed loop stayed autonomous after the initial user turn and completed without manual mid-turn steering.
- The run exercised the real `Core Matrix` plus Dockerized `Fenix` path instead of a debug-only shortcut.
- The final product landed in the mounted host workspace and was independently runnable from the host.
- The tool surface stayed stable, but this run did not export subagent evidence, so subagent capability should be probed again on the next capstone rerun.

## Where Operator Intervention Was Still Needed

- For realistic coding-agent capstone runs, the smaller live-acceptance selector was not sufficient. The full-window selector `candidate:openrouter/openai-gpt-5.4` was the correct operational choice.
- Removed container-built node_modules before host validation.

## Collaboration Guidance

- Keep the workspace disposable and expect a host-side dependency reinstall when the container writes platform-specific JavaScript dependencies into a shared mount.
- Treat the provider-backed loop as the truth for acceptance. The agent message alone was not enough; the durable workflow, subagent session, export bundle, and host playability checks were needed to close the run.
- Keep the staged GitHub skill sources in the mounted workspace so the runtime can install and inspect them through the normal tool surface.
