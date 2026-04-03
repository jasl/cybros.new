# Acceptance Harness

Top-level acceptance automation lives here so `Core Matrix` and `Fenix` stay
independent product codebases.

- `bin/` contains shell orchestrators for fresh-start and capstone runs.
- `scenarios/` contains Ruby acceptance scenarios.
- `lib/` contains harness-only support code.
- `artifacts/` and `logs/` are generated output directories and should stay out
  of git.

Run acceptance scenarios through `Core Matrix`'s Rails environment:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
cd core_matrix
bin/rails runner ../acceptance/scenarios/<scenario>.rb
```

Run the 2048 capstone with a fresh stack:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

`acceptance/Gemfile` reserves a dedicated top-level home for the harness, but
the supported execution path currently goes through `core_matrix/bin/rails`
so the acceptance scripts reuse the product Rails environment directly.
