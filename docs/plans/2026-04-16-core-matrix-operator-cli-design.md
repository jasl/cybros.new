# CoreMatrix Operator CLI Design

## Goal

Add a monorepo-local but deployment-independent operator CLI that talks to the
CoreMatrix HTTP API and can take a fresh installation from first bootstrap to
"ready for real-world integration testing" without requiring the website UI.

The first version should cover the core path only:

- bootstrap the first admin once
- log in and persist CLI credentials
- inspect installation readiness
- complete Codex subscription authorization
- create or select a workspace when needed
- attach a workspace agent when needed
- configure Telegram ingress
- configure Weixin ingress

## Problem

The repository is close to product-complete on the backend side, including
recent Telegram and Weixin ingress work, but there is not yet a practical
operator-facing surface for turning a new CoreMatrix deployment into a usable
system.

Today:

- CoreMatrix already exposes admin/provider/workspace/workspace-agent/ingress
  APIs, but they assume an existing authenticated app session.
- CoreMatrix does not expose a CLI-friendly first-bootstrap or
  email/password login endpoint.
- The Telegram and Weixin ingress API currently creates bindings and supports
  Weixin login lifecycle actions, but it does not yet offer a clean operator
  path for writing Telegram connector credentials/configuration.
- The monorepo has no dedicated CLI project for CoreMatrix.

Without a CLI, the next stage of complex environment validation is blocked on a
missing operator setup surface rather than missing business capabilities.

## Recommendation

Build a hybrid **A + C** architecture:

- **A: API-first CLI**
  - create a new top-level Ruby project `core_matrix_cli/`
  - implement the CLI with Thor
  - keep the CLI deployment-independent by talking only to CoreMatrix HTTP APIs
- **C: reuse onboarding/pairing where it already fits**
  - preserve `OnboardingSession` for machine/runtime registration
  - preserve provider authorization flows such as Codex OAuth
  - do **not** turn first-admin bootstrap or human login into onboarding tokens

This keeps the CLI real and remotely usable while avoiding a second ad hoc
configuration world outside the existing CoreMatrix pairing model.

## Design Principles

1. The CLI is an operator surface, not a second app backend.
2. Human authentication uses `Session`; machine/runtime pairing uses
   `OnboardingSession`.
3. CoreMatrix remains the source of truth for credentials, connector runtime
   state, and readiness.
4. The CLI stores only what it needs to operate: base URL, session token, and
   current selection context.
5. Initialization must be resumable. Re-running `cmctl init` should continue
   from current server state instead of replaying steps blindly.
6. V1 should be intentionally narrow. It must optimize for the "turn a fresh
   install into a usable test system" path rather than broad administrative
   coverage.

## Existing CoreMatrix Capabilities We Should Reuse

### Bundled bootstrap side effects

`Installations::BootstrapFirstAdmin` already creates the first installation and
admin user, and then delegates to
`Installations::BootstrapBundledAgentBinding` when bundled agent support is
enabled.

That bootstrap path can already create:

- the bundled agent
- the bundled execution runtime
- a default workspace
- an active `WorkspaceAgent` mount

So after bootstrap, the CLI should **re-read server state** rather than assume
workspace and agent attachment are still missing.

### Provider authorization

CoreMatrix already has a working Codex Subscription OAuth flow under
`/app_api/admin/llm_providers/codex_subscription/authorization`.

The CLI should reuse that flow exactly:

- request an authorization URL
- open it locally when possible
- poll provider authorization status until success, timeout, or failure

### Ingress binding lifecycle

CoreMatrix already supports:

- creating Telegram or Weixin ingress bindings
- returning Telegram webhook path setup information
- starting Weixin QR login
- polling Weixin login status
- disconnecting Weixin bindings

The missing piece is a CLI-safe operator path for Telegram connector
credential/config writes.

## Proposed Architecture

### 1. New top-level project: `core_matrix_cli/`

Add a new monorepo subproject:

- `core_matrix_cli/Gemfile`
- `core_matrix_cli/.ruby-version`
- `core_matrix_cli/bin/cmctl`
- `core_matrix_cli/lib/core_matrix_cli/...`
- `core_matrix_cli/test/...`

The CLI should remain small and explicit:

- Thor for command surface
- a dedicated HTTP client layer
- a local credential/config storage abstraction
- small presenter helpers for human-readable output

It must **not** boot Rails or call into CoreMatrix internals directly.

### 2. Thin operator/admin HTTP API additions in CoreMatrix

Add the minimum missing API surface:

- `GET /app_api/bootstrap/status`
- `POST /app_api/bootstrap`
- `GET /app_api/session`
- `POST /app_api/session`
- `DELETE /app_api/session`
- `POST /app_api/workspaces`
- extend ingress binding update flow to support connector credential/config
  writes for the binding's single active connector

The CLI then composes those endpoints with existing admin/workspace/provider
APIs.

### 3. Keep onboarding tokens machine-only

Do not overload `OnboardingSession` with human bootstrap/login.

Correct separation:

- **human operator**
  - `Session`
- **runtime/agent pairing**
  - `OnboardingSession`
- **provider OAuth**
  - `ProviderAuthorizationSession`

This keeps token semantics bounded and avoids mixing web-login state with
runtime registration state.

## Operator Flows

### `cmctl init`

`cmctl init` is the main orchestration entry point. It should be resumable and
state-driven.

Flow:

1. Read `bootstrap/status`.
2. If `unbootstrapped`, prompt for first-admin bootstrap data and call
   `POST /app_api/bootstrap`.
3. Persist the returned `session_token` automatically.
4. If `bootstrapped`, ensure the operator is logged in, prompting through
   `POST /app_api/session` if needed.
5. Query installation, workspaces, workspace agents, provider state, and
   ingress state.
6. Continue only through missing steps.

The command should never assume the previous partial run completed.

### `cmctl auth login`

Email/password login flow:

- prompt for base URL if not configured
- prompt for email and password
- call `POST /app_api/session`
- persist returned session token automatically

### `cmctl auth whoami`

Session inspection:

- call `GET /app_api/session`
- show current user, role, installation name, and token expiry if present

### `cmctl auth logout`

Logout flow:

- call `DELETE /app_api/session`
- clear locally stored session token regardless of remote outcome

### `cmctl status`

Status must be derived from real server state, not from a local wizard log.

At minimum it should report:

- authenticated or not
- installation bootstrapped or not
- default workspace present or not
- active workspace agent present or not
- Codex Subscription authorized/usable or not
- Telegram configured or not
- Weixin connected or not

### `cmctl providers codex login`

Flow:

1. `POST /app_api/admin/llm_providers/codex_subscription/authorization`
2. receive `authorization_url`
3. open it locally when possible; otherwise print it
4. poll `GET .../authorization`
5. stop when status is `authorized`, `reauthorization_required`, or timeout

### `cmctl ingress telegram setup`

Flow:

1. create binding if absent
2. collect bot token and webhook base URL
3. write connector credential/config through CoreMatrix
4. print final webhook URL as:
   `webhook_base_url + setup.webhook_path`
5. optionally run a connection test if the API exposes one in this round

### `cmctl ingress weixin setup`

Flow:

1. create binding if absent
2. if binding already exists, check login status first
3. if not connected, call `weixin/start_login`
4. show returned QR code URL
5. poll `weixin/login_status`
6. stop when connected, timed out, or explicitly cancelled

Weixin setup is naturally resumable because the server owns the current login
state.

## Credentials and Local Storage

The CLI should automatically save successful login credentials, but only its
own operator credential.

Store locally:

- `base_url`
- `session_token`
- optional convenience context:
  - `workspace_id`
  - `workspace_agent_id`
  - operator email for display only

Do **not** store locally:

- admin password
- Codex OAuth access/refresh tokens
- Telegram bot token
- Weixin account credentials/runtime state

Storage strategy:

- prefer OS keychain/keyring when available
- otherwise fall back to a local config file with `0600` permissions

When the server returns `401`, expired-session, or revoked-session semantics,
the CLI should clear the saved token and require re-login.

## API Design

### Public bootstrap endpoints

#### `GET /app_api/bootstrap/status`

Unauthenticated, safe, read-only.

Returns:

- `bootstrap_state`: `unbootstrapped` or `bootstrapped`
- optional installation summary when bootstrapped

#### `POST /app_api/bootstrap`

Unauthenticated, one-time operation.

Input:

- installation name
- admin email
- password
- password confirmation
- display name

Behavior:

- reuse `Installations::BootstrapFirstAdmin`
- immediately issue a normal app `Session`
- return:
  - installation summary
  - user summary
  - session token
  - any default workspace/workspace-agent summary already created by bundled
    bootstrap logic

If already bootstrapped, return a stable error payload rather than trying to
partially bootstrap again.

### Session endpoints

#### `POST /app_api/session`

Input:

- email
- password

Behavior:

- find enabled `Identity` by normalized email
- authenticate with `has_secure_password`
- issue a `Session`
- return user/installation/session summary plus plaintext token

#### `GET /app_api/session`

Authenticated.

Returns:

- current user summary
- installation summary
- session metadata

#### `DELETE /app_api/session`

Authenticated.

Behavior:

- revoke current session
- return success even if the client is about to discard its token anyway

### Workspace creation

#### `POST /app_api/workspaces`

Authenticated.

Input:

- `name`
- optional `privacy`
- optional `is_default`

Behavior:

- create a private workspace for the current user
- enforce per-user default uniqueness when `is_default=true`
- do not implicitly create a mount in the generic API path

The CLI can attach a workspace agent separately via the existing
`workspace_agents#create` endpoint.

### Ingress connector configuration

V1 should keep the current one-binding-one-primary-connector mental model.

Rather than adding a brand new public connector resource family, extend the
existing ingress binding update path to accept a nested `channel_connector`
payload that applies to the binding's connector.

Allowed update fields in V1:

- `label`
- `lifecycle_state`
- `credential_ref_payload`
- `config_payload`

For Telegram, the service layer should validate the minimal required fields and
return operator-friendly errors.

## CLI Behavior After Bootstrap

Because bundled bootstrap can already create a default workspace and active
workspace agent, the CLI should not assume these are missing after a fresh
bootstrap.

Correct post-bootstrap behavior:

1. save the returned session token
2. query installation/workspace/provider state
3. skip workspace and agent setup if already present
4. continue directly to provider or ingress steps as needed

## Non-Goals for V1

This round intentionally does **not** include:

- a full website-equivalent management surface
- generalized connector management for every future platform
- storing business credentials locally in the CLI
- replacing existing onboarding/pairing semantics
- broad destructive admin workflows
- a heavy server-side wizard state machine

## Verification Strategy

### CoreMatrix

Add request/service coverage for:

- bootstrap status
- first bootstrap success/failure
- session login/show/logout
- workspace create
- Telegram connector config update

Extend existing request tests for:

- Codex authorization polling flow
- Weixin login status flow

### CLI

Add command/client coverage for:

- `init`
- `auth login`
- `auth whoami`
- `auth logout`
- `status`
- `providers codex login`
- `ingress telegram setup`
- `ingress weixin setup`

### Minimum end-to-end acceptance target

The v1 definition of done is a reproducible path that can:

1. bootstrap a fresh CoreMatrix deployment
2. automatically persist operator login credentials
3. reuse bundled workspace/agent state when present
4. authorize Codex Subscription
5. configure Telegram or connect Weixin
6. report readiness through `cmctl status`

At that point, the CLI has done its job: the system is ready for the next round
of real integration testing without depending on the website UI.
