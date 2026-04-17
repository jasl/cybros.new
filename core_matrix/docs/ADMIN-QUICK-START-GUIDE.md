# CoreMatrix Admin Quick Start Guide

This guide starts after the CoreMatrix services are already running.

If the installation is not deployed yet, start with
[INSTALL.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/INSTALL.md).

## 1. Bootstrap The Installation

Run:

```bash
cd core_matrix_cli
bundle exec ./bin/cmctl init
```

If you are running on the CoreMatrix host itself, use:

```text
http://127.0.0.1:3000
```

If you are operating from another machine on the same LAN, use the
operator-facing LAN or HTTPS hostname instead.

## 2. Confirm Operator Access

Run:

```bash
bundle exec ./bin/cmctl status
bundle exec ./bin/cmctl auth whoami
```

Healthy early state looks like:

- installation present
- authenticated yes
- bootstrap state `bootstrapped`
- workspace may still be missing
- workspace agent may still be missing

## 3. Create A Workspace

Run:

```bash
bundle exec ./bin/cmctl workspace create --name "Staging" --default
bundle exec ./bin/cmctl workspace list
bundle exec ./bin/cmctl status
```

## 4. Authorize Codex

Run:

```bash
bundle exec ./bin/cmctl providers codex login
```

This uses OpenAI device flow. Expect:

1. a verification URL
2. a user code
3. optional browser launch
4. polling until authorization completes

Check later with:

```bash
bundle exec ./bin/cmctl providers codex status
```

## 5. Understand The Current Empty State

After a CoreMatrix-only deployment, this is normal:

- `selected workspace agent: missing`
- `cmctl agent attach` cannot succeed yet
- Telegram and Weixin setup are blocked on having a workspace agent

That is not a CoreMatrix deployment failure. It only means the agent side has
not been deployed yet.

## 6. Watch The Right Things

On the CoreMatrix host:

```bash
cd /home/jasl/cybros/core_matrix
docker compose ps
docker compose logs --tail=80 app jobs
```

Health checks:

```bash
curl -fsS http://127.0.0.1:3000/up
curl -fsS http://127.0.0.1:3000/app_api/bootstrap/status
```

## 7. Add Integrations In The Right Order

Recommended order:

1. CoreMatrix bootstrap
2. workspace creation
3. Codex authorization
4. deploy an agent and attach a workspace agent
5. Telegram polling
6. only later, Telegram webhook if public HTTPS exists

For integration-specific details, use
[INTEGRATIONS.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/INTEGRATIONS.md).

## 8. Know The Current Product Boundary

Current `cmctl` is intentionally narrow. It is strong at:

- first-run bootstrap
- operator login
- workspace creation and selection
- Codex authorization
- IM setup preparation

It is not yet a full administration surface.
