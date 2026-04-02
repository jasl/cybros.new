# Playability Verification

Runtime-side verification:
- selected output message present: `true`
- agent reported browser verification in final output: `true`

Debug evidence:
- browser tool calls observed: `2`
- durable command runs exported: `19`
- durable process runs exported: `0`

Host-side validation:
- see `workspace-validation.md`
- host-side dependency reinstalls caused by platform-specific `node_modules` are treated as operational validation steps, not as agent-quality failures
