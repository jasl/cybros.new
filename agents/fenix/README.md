# Fenix

`fenix` is the default out-of-the-box agent program for Core Matrix.

Fenix has two jobs:

- ship as a usable general assistant product
- serve as the first technical validation program for the Core Matrix loop

## Product Definition

Fenix is a practical assistant that combines:

- general-assistant conversation behavior inspired by `openclaw`
- coding-assistant behavior inspired by Codex-style workflows
- everyday office-assistance behavior inspired by `accomplish` and `maxclaw`

Fenix may define agent-specific tools, deterministic program logic, and
composer completions such as slash commands or symbol-triggered references. It
does not need every interaction to be driven by an LLM.

## Boundary

Fenix is not:

- the kernel itself
- the home for every future product shape
- a universal agent meant to absorb all future experiments

When Core Matrix needs to validate materially different product shapes, those
should land in separate agent programs rather than forcing them into Fenix.

## Phase Role

- `Phase 2`: prove the real agent loop end to end
- `Phase 3`: become the first full Web product on top of the validated kernel
- `Phase 4`: remain one validated product while other agent programs prove the
  kernel is reusable beyond Fenix
