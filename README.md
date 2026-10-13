# Roblox game project scaffold

A starting point for a new roblox-ts game: roblox-ts + Rojo + Flamework + React, tests that run
both headlessly and in Studio, and CI. Extracted from Hearthstead once its foundation was finished
and proven, with nothing game-specific left in.

## What's here

| | |
|---|---|
| `roblox-ts-scaffold-guide.md` | The guide. Hand this to an agent in an empty repo. Explains the layout, the reasoning, and the gotchas that are hard to diagnose from their symptoms. |
| `template/` | The reusable files themselves, ready to copy. Project names are placeholders. |

## Using it

Give an agent the guide and point it at `template/`, e.g.:

> Scaffold a new Roblox game project in this empty repo. Follow
> `<path>/roblox-ts-scaffold-guide.md`, copying files from `<path>/template/` where they fit.
> The game is called "<name>". Ask me the questions in the guide's "Ask first" section before
> starting.

Copying beats regenerating for `scripts/lune/rbx.luau` in particular — it is ~525 lines of virtual
DataModel, it is what makes headless tests possible at all, and it is the single hardest piece to
rebuild from a description.

## Placeholders

Replace in every file under `template/`:

| Placeholder | Meaning | Appears in |
|---|---|---|
| `__GAME_NAME__` | Display name, e.g. `Hearthstead` | the four `*.project.json`, `eslint.config.mjs`, `scripts/lunit-tags.luau` |
| `__GAME_SLUG__` | npm package name, e.g. `hearthstead` | `package.json` |

## Not included

The template is the foundation only. A new project still needs its own:

- `src/` — the template ships no game code. The guide describes the folder layout to create.
- `tests/` and `stories/` — create them mirroring `src/`, as the guide explains.
- `CLAUDE.md`, docs and agent definitions.
- A `.mcp.json` if the project uses the Roblox Studio MCP server.

Dependency versions in `package.json` are pinned as of 2026-09-12. Check for newer releases when
starting a project — but read gotcha 1 in the guide before changing the TypeScript pin, which must
match whatever roblox-ts bundles.
