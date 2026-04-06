# Acceptance Harness

Top-level acceptance automation lives here so `Core Matrix` and `Fenix` stay
independent product codebases.

- `bin/` contains shell orchestrators for fresh-start and capstone runs.
- `scenarios/` contains Ruby acceptance scenarios.
- `lib/` contains harness-only support code.
- `artifacts/` and `logs/` are generated output directories and should stay out
  of git.

The 2048 capstone now writes an organized artifact bundle per run:

- `review/` for human-readable transcripts, supervision views, and validation notes
- `evidence/` for machine-readable benchmark outputs and diagnostics
- `logs/` for timeline and supervision logs
- `exports/` for export/debug-export/import roundtrip bundles and metadata
- `playable/` for host-side build, preview, and browser-verification outputs
- `tmp/` for unpacked debug bundles and scratch files

Each bundle also includes:

- a root `README.md` for compatibility
- `review/index.md` as the human-readable entry point
- `evidence/artifact-manifest.json` as the canonical machine-readable entry point

New callers should prefer `review/`, `evidence/`, and `logs/` instead of the
legacy root-level duplicates.

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
