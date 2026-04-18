# Nexus

`execution_runtimes/nexus` is the active Nexus execution runtime for this
monorepo. It ships as the `cybros_nexus` gem and exposes the installed
`nexus` executable for operators.

## Operator Entry Points

Install the packaged gem and inspect the installed executable:

```bash
gem install cybros_nexus
nexus --help
nexus run --help
```

Start the runtime supervisor with:

```bash
nexus run
```

For development inside the monorepo, use the local executable shim instead of
the installed gem binary:

```bash
bundle install
./exe/nexus --help
./exe/nexus run --help
./exe/nexus run
```

## Container Image

`execution_runtimes/nexus` also publishes a container image that installs the
packaged gem on top of the `images/nexus` toolchain base. For multi-arch
releases, `NEXUS_BASE_IMAGE` must already point at a multi-arch image that
includes both `linux/amd64` and `linux/arm64`.

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg NEXUS_BASE_IMAGE=ghcr.io/your-org/nexus-base:latest \
  -f execution_runtimes/nexus/Dockerfile \
  -t ghcr.io/your-org/nexus-runtime:latest \
  --push \
  execution_runtimes/nexus
```

## Required Environment

`nexus run` requires:

- `CORE_MATRIX_BASE_URL`: CoreMatrix base URL, for example `http://127.0.0.1:3000`
- one of:
  - `NEXUS_ONBOARDING_TOKEN` or `CORE_MATRIX_ONBOARDING_TOKEN` to open a fresh runtime session
  - `CORE_MATRIX_EXECUTION_RUNTIME_CONNECTION_CREDENTIAL` to resume an existing runtime session

Optional environment:

- `NEXUS_HOME_ROOT`: durable runtime home root, default `~/.nexus`
- `NEXUS_PUBLIC_BASE_URL`: override the public base URL advertised in the runtime manifest
- `NEXUS_HTTP_BIND` / `NEXUS_HTTP_PORT`: local manifest server bind address and port
- `NEXUS_NODE_COMMAND`: Node executable used by the browser host

## State Root

The runtime stores durable local state under `NEXUS_HOME_ROOT`:

- `state.sqlite3`
- `memory/`
- `skills/`
- `logs/`
- `tmp/`

`state.sqlite3` is the canonical SQLite journal for sessions, mailbox receipts,
execution attempts, resource handles, and the event outbox.

## Verification

Run the project checks from this directory:

```bash
bundle exec rake test
bundle exec rubocop
```

Packaged-gem smoke from a clean temporary `GEM_HOME`:

```bash
rm -rf tmp/package_smoke
mkdir -p tmp/package_smoke/gems tmp/package_smoke/home
rm -f cybros_nexus-*.gem
bundle exec gem build cybros_nexus.gemspec
GEM_HOME="$PWD/tmp/package_smoke/gems" \
GEM_PATH="$PWD/tmp/package_smoke/gems" \
gem install --no-document --install-dir "$PWD/tmp/package_smoke/gems" ./cybros_nexus-*.gem
HOME="$PWD/tmp/package_smoke/home" \
GEM_HOME="$PWD/tmp/package_smoke/gems" \
GEM_PATH="$PWD/tmp/package_smoke/gems" \
PATH="$PWD/tmp/package_smoke/gems/bin:$PATH" \
nexus --help
HOME="$PWD/tmp/package_smoke/home" \
GEM_HOME="$PWD/tmp/package_smoke/gems" \
GEM_PATH="$PWD/tmp/package_smoke/gems" \
PATH="$PWD/tmp/package_smoke/gems/bin:$PATH" \
nexus run --help
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
