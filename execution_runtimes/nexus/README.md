# CybrosNexus

CybrosNexus is the Nexus execution runtime rebuild for the Cybros monorepo.
It packages the runtime as a Ruby gem so operators can install one artifact and
start the runtime through the `nexus` executable.

## Installation

For local development inside the monorepo:

```bash
bundle install
bundle exec ./exe/nexus --help
```

The packaged runtime will eventually be installed with:

```bash
gem install cybros_nexus
nexus run
```

## Commands

```bash
nexus --help
nexus run
nexus version
```

`nexus run` is the operator entrypoint for the runtime supervisor. In this
initial rewrite stage it is only a CLI stub; later tasks connect it to the new
runtime kernel.

## Development

Run the targeted test suite from this project root:

```bash
bundle exec rake test
bundle exec rubocop
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
