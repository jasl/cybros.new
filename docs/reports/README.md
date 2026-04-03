# Reports

This directory now stores authored reports that are part of the repository,
such as architecture audits and narrative write-ups.

Generated acceptance logs, proof bundles, screenshots, exports, and other
runtime artifacts no longer belong here. The top-level acceptance harness owns
those outputs and writes them to:

- `/Users/jasl/Workspaces/Ruby/cybros/acceptance/logs/`
- `/Users/jasl/Workspaces/Ruby/cybros/acceptance/artifacts/`

Those runtime outputs are intentionally gitignored.
