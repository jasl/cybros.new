# Core Matrix CLI

`core_matrix_cli` is the standalone operator CLI for bringing a CoreMatrix
installation into a usable state before the web UI covers the full setup path.

## Installation

For local monorepo development:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle install
```

For packaged distribution:

```bash
gem install core_matrix_cli
```

The executable entrypoint is `cmctl`. Inside this repository, the supported
black-box invocation is:

```bash
bundle exec exe/cmctl
```

## Quickstart

```bash
bundle exec exe/cmctl init
bundle exec exe/cmctl providers codex login
bundle exec exe/cmctl ingress telegram setup
bundle exec exe/cmctl ingress telegram-webhook setup
bundle exec exe/cmctl ingress weixin setup
bundle exec exe/cmctl status
```

If `init` cannot reuse a bundled workspace and workspace agent, create and
select them explicitly:

```bash
bundle exec exe/cmctl workspace create --name "Integration Lab"
bundle exec exe/cmctl agent attach --workspace-id <workspace_id> --agent-id <agent_id>
```

## Command Groups

- `bundle exec exe/cmctl init`
- `bundle exec exe/cmctl auth login`
- `bundle exec exe/cmctl auth whoami`
- `bundle exec exe/cmctl auth logout`
- `bundle exec exe/cmctl status`
- `bundle exec exe/cmctl providers codex login`
- `bundle exec exe/cmctl providers codex status`
- `bundle exec exe/cmctl providers codex logout`
- `bundle exec exe/cmctl workspace list`
- `bundle exec exe/cmctl workspace create`
- `bundle exec exe/cmctl workspace use <workspace_id>`
- `bundle exec exe/cmctl agent attach --agent-id <agent_id>`
- `bundle exec exe/cmctl ingress telegram setup`
- `bundle exec exe/cmctl ingress telegram-webhook setup`
- `bundle exec exe/cmctl ingress weixin setup`

## Integrations

Operator-facing integration guidance lives inside this project:

- [docs/integrations.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/docs/integrations.md)

For command-specific prompts and prerequisites, the help tree is also part of
the contract:

```bash
bundle exec exe/cmctl ingress telegram help setup
bundle exec exe/cmctl ingress telegram-webhook help setup
bundle exec exe/cmctl ingress weixin help setup
```

## Local Development

Install dependencies and prepare the local checkout:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bin/setup
```

Primary verification commands:

```bash
bundle exec rake test
bundle exec rubocop --no-server
bundle exec rake build
```

Use `bin/console` for an interactive shell against the rebuilt gem.

## License

`core_matrix_cli` is licensed under the MIT License. See
[LICENSE.txt](/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/LICENSE.txt).
