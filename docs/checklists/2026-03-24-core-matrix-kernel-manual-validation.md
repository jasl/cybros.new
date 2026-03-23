# Core Matrix Kernel Manual Validation Checklist

## Status

Living checklist for real-environment verification during the backend greenfield build.

The implementation phase must keep this document updated. Each complex flow should end with exact commands, setup notes, and expected outcomes that can be reproduced later.

## Prerequisites

- `cd core_matrix`
- application boots under `bin/dev`
- test or development data needed for the target flow is documented inline
- any helper scripts or dummy agent processes used for validation are referenced inline

## Flows To Maintain

- first-admin bootstrap
- invitation creation and consumption
- admin grant and revoke
- bundled Fenix auto-registration and first-admin auto-binding when configured
- agent enrollment, registration, handshake, heartbeat, and outage recovery
- drift-triggered manual resume and manual retry
- user-agent binding and default workspace creation
- provider catalog load and governance changes
- conversation root creation, branch creation, thread creation, checkpoint creation, archive and unarchive
- conversation tail edit, rollback or fork editing, retry, rerun, swipe selection, queued turn handling, and runtime pinning
- attachments, imports, summary segments, visibility overlays, multimodal model access, and unsupported-capability fallback behavior
- workflow scheduling, approvals, short-lived turn commands, long-lived background services, process output replay, subagent runs, and lease recovery
- publication create, read-only projection, access logging, and revoke

## Checklist Template

For each flow, keep:

- goal
- prerequisites
- exact commands
- exact endpoints or console actions
- expected rows or state changes
- expected logs or visible outcomes
- cleanup steps
