# Fenix Skills And Agent Skills Spec Research Note

## Status

Recorded research for future `Fenix` and `Core Matrix` planning.

This note captures stable conclusions from local reference material. It should
remain understandable even if `references/` changes later.

## Decision Summary

- Keep skills on the `Fenix` agent-program side in Phase 2.
- Treat `Fenix` as an Agent Skills-compatible client for third-party skills.
- Allow `Fenix` to keep private system skills that are not meant to be portable
  across clients.
- Separate skill classes explicitly:
  - platform system skills under `.system`
  - bundled curated catalog entries under `.curated`
  - live installed third-party skills under the normal `skills/<name>/` root
- Adopt progressive disclosure rather than eagerly loading full skill bodies.

## Stable Findings From The Agent Skills Spec

The most durable patterns from the Agent Skills material are:

- a skill is a directory with at least `SKILL.md`
- optional folders such as `scripts/`, `references/`, and `assets/` are normal
- the key portable metadata is the `SKILL.md` frontmatter, especially
  `name` and `description`
- the core client behavior is progressive disclosure:
  - disclose a lightweight catalog first
  - load the full `SKILL.md` only when activated
  - load bundled resources on demand
- a dedicated activation or loader tool is a normal integration pattern
- bundled resource files should be listed without being eagerly loaded

These patterns matter more than any one prompt format or example client.

## Practical Client Guidance Worth Keeping

The upstream client-implementation guidance surfaced several points that fit
`Fenix` well:

- scan deterministic skill roots instead of relying on one huge monolithic
  prompt
- prefer a stable catalog shape so the model knows what skills exist
- allow on-demand loading through dedicated skill tools
- resolve referenced files relative to the skill root
- keep skill content available for the rest of the active session instead of
  silently dropping it too early

The same guidance also recommends lenient parsing for imperfect third-party
skills. `Fenix` should apply this carefully: enough leniency to install real
third-party skills, but not so much leniency that corrupted packages quietly
become live.

## Fenix Adoption Rules

For Phase 2, `Fenix` should adopt the following rules:

- standard third-party skill packages should install and activate when they
  follow the normal Agent Skills layout
- `Fenix` may add private system skills that rely on agent-specific semantics
- `.system` skill names are reserved and cannot be overridden
- `.curated` entries are bundled catalog sources rather than the primary live
  installation root
- live installed third-party skills should appear under `skills/<name>/`
- installation should use staged promotion, provenance, and snapshot-friendly
  replacement

## Surface Worth Copying From Claw

The most useful implementation pattern in the local `claw` reference is its
minimal skill tool surface:

- `skills_catalog_list`
- `skills_load`
- `skills_read_file`
- `skills_install`

The installation service also captures several good guardrails:

- reject collisions with platform-owned skills
- install via staging and promotion
- snapshot old live skills before replacement
- write provenance metadata for installed skills
- support the rule that refreshed skills only become effective on the next
  top-level turn

These patterns are more useful to `Fenix` than any attempt to copy the entire
`claw` runtime shape.

## Deliberate Non-Adoption In Phase 2

Phase 2 does not need to adopt every idea from the upstream materials.

Specifically, it should not require:

- a kernel-level skills system in `Core Matrix`
- a marketplace or plugin ecosystem
- a promise that every client-specific prompt wrapper is replicated exactly
- completion-surface standardization for slash commands or mention syntax

## Re-Evaluation Triggers

Re-open this note when one of these happens:

- `Fenix` needs richer skill lifecycle operations such as uninstall or policy
  gating
- the Web UI needs explicit installed-skill management surfaces
- a second agent program wants to share the same skills implementation
- the platform starts planning extension or plugin packaging

## Reference Index

These references informed the note, but they are not the source of truth.

Local monorepo references:

- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/agentskills/docs/specification.mdx](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/agentskills/docs/specification.mdx)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/agentskills/docs/client-implementation/adding-skills-support.mdx](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/agentskills/docs/client-implementation/adding-skills-support.mdx)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/agentskills/docs/what-are-skills.mdx](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/agentskills/docs/what-are-skills.mdx)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/openai-skills/skills/.system](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/openai-skills/skills/.system)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/openai-skills/skills/.curated](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/openai-skills/skills/.curated)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/agents/claw/lib/cybros/agents/claw/skill_installation_service.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/agents/claw/lib/cybros/agents/claw/skill_installation_service.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/agents/claw/test/integration/rpc_contract_test.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/agents/claw/test/integration/rpc_contract_test.rb)

External reference used as a future manual-validation target:

- [obra/superpowers](https://github.com/obra/superpowers)
