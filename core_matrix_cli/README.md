# Core Matrix CLI

Thor-based operator CLI for CoreMatrix.

## Quickstart

```bash
bundle exec ./bin/cmctl init
bundle exec ./bin/cmctl providers codex login
bundle exec ./bin/cmctl ingress telegram setup
bundle exec ./bin/cmctl ingress telegram-webhook setup
bundle exec ./bin/cmctl ingress weixin setup
bundle exec ./bin/cmctl status
```

If `cmctl init` does not reuse a bundled workspace and workspace agent, create
and select them before IM setup:

```bash
bundle exec ./bin/cmctl workspace create --name "Integration Lab"
bundle exec ./bin/cmctl agent attach --workspace-id <workspace_id> --agent-id <agent_id>
```

## Operator Focus

`cmctl` is intentionally narrow in v1. It is for operator setup, not full
administration. The implemented happy path is:

- bootstrap or log into a CoreMatrix installation
- persist the operator session locally
- create and select a workspace
- attach an agent to that workspace
- authorize Codex Subscription
- configure Telegram polling and optionally Telegram webhook, or drive the Weixin QR login contract
- inspect the current readiness snapshot

## Command Groups

- `cmctl init`
- `cmctl auth login|whoami|logout`
- `cmctl status`
- `cmctl providers codex login|status|logout`
- `cmctl workspace list|create|use`
- `cmctl agent attach`
- `cmctl ingress telegram setup`
- `cmctl ingress telegram-webhook setup`
- `cmctl ingress weixin setup`

## IM Preparation

The canonical operator entrypoint for IM prerequisites is built into the
command help:

```bash
bundle exec ./bin/cmctl ingress telegram help setup
bundle exec ./bin/cmctl ingress telegram-webhook help setup
bundle exec ./bin/cmctl ingress weixin help setup
```

The longer companion guide is available at
[docs/operations/core-matrix-im-preparation-guide.md](/Users/jasl/Workspaces/Ruby/cybros/docs/operations/core-matrix-im-preparation-guide.md).

## Verification Boundary

Telegram and Weixin self-verification in v1 is API-contract only. The CLI can
prove polling setup, webhook material exposure, connector writes, QR rendering,
and status polling. Real Telegram delivery and human QR scans remain later
joint integration work.
