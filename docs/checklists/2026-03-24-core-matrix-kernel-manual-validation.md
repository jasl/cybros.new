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
- agent enrollment, registration, handshake, heartbeat, outage recovery, and deployment retirement
- drift-triggered manual resume and manual retry
- user-agent binding and default workspace creation
- provider catalog load, governance changes, and related audit rows
- conversation root creation, automation root creation, branch creation, thread creation, checkpoint creation, archive and unarchive
- conversation interactive selector `auto | explicit candidate`, tail edit, rollback or fork editing, retry, rerun, swipe selection, queued turn handling, and runtime pinning
- automation turn creation without a transcript-bearing user message, persisted turn-origin metadata, and read-only automation history inspection
- attachments, imports, summary segments, visibility overlays, multimodal model access, and unsupported-capability fallback behavior
- workflow scheduling, dynamic DAG expansion, fan-out or fan-in joins, structured wait-state transitions, role-local model fallback after entitlement exhaustion, explicit-candidate no-fallback failure, approvals, human form requests, human task requests, same-workflow human-interaction resumption, short-lived turn commands, long-lived background services, process output replay, subagent runs, lightweight swarm coordination metadata, canonical variable writes and promotions, and lease recovery
- replaceable live projection streams for streaming text, progress, and status surfaces while preserving append-only event history
- agent transcript cursor pagination and canonical variable API reads through machine-facing endpoints
- machine credential rotation and revocation
- one-time selector override during manual recovery
- publication internal-public access, external-public access, read-only projection, access logging, and revoke

## Checklist Template

For each flow, keep:

- goal
- prerequisites
- exact commands
- exact endpoints or console actions
- expected rows or state changes
- expected logs or visible outcomes
- cleanup steps
