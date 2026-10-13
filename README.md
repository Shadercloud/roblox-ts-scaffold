# roblox-ts game scaffold

The project setup behind Hearthstead, a Roblox game written in TypeScript. It's the foundation only: config files,
build scripts and test runners, with nothing game-specific in it.

What it sets up:

- **TypeScript instead of Luau**, compiled by [roblox-ts](https://roblox-ts.com/).
- **Rojo** to sync your code from VS Code into Roblox Studio as you save.
- **React** for UI, **Flamework** for services and networking, **Charm** for game state.
- **Tests you can run from the command line** in a couple of seconds, without opening Studio, plus the same
  tests inside Studio.
- **Lint, formatting and GitHub Actions CI** on every push.

## What's in the repo

| Path | What it is |
|---|---|
| `template/` | The files to copy into your own project: configs, build scripts and test runners |
| `roblox-ts-scaffold-guide.md` | The full guide: the folder layout, why it's built this way, and the problems that cost the most time to track down |

The template has **no game code** (`src/`), tests or UI stories yet. You create those in your own project, and the
guide shows where each one goes.

## Using it

1. Copy everything in `template/` into an empty folder for your game.
2. Replace the two placeholders in every file:

   | Placeholder | Replace with | Example |
   |---|---|---|
   | `__GAME_NAME__` | Your game's display name | `Hearthstead` |
   | `__GAME_SLUG__` | A lowercase package name, no spaces | `hearthstead` |

3. Follow `roblox-ts-scaffold-guide.md` to create the `src/`, `tests/` and `stories/` folders.

You can also give the guide and the `template/` folder to an AI coding agent and ask it to set up the project for
you. The guide is written so an agent can follow it step by step.

### Keep `scripts/lune/rbx.luau` as it is

Whether you set things up by hand or with an agent, copy this file rather than rewriting it.

Code compiled by roblox-ts expects to run inside a Roblox game: every file starts by looking things up with
`game:GetService(...)`. Outside Studio there is no `game`, so the code can't even load. `rbx.luau` fixes that by
building a stand-in for the Roblox game tree from your Rojo project file. The same compiled code then runs under
[Lune](https://lune-org.github.io/docs) on the command line, and that's what lets `npm test` work without Studio.

It's about 525 lines and fiddly to get right, so don't try to regenerate it from a description.

## Versions

Package versions in `template/package.json` were current on 2026-09-12. Newer ones are usually fine, with one
exception: **TypeScript must stay at exactly the version roblox-ts uses internally** (`5.5.3` for roblox-ts 3.0).
Gotcha 1 in the guide explains why.

## License

MIT. See `LICENSE`. Use it for any project, commercial or not.
