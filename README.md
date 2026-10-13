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

| Path | What it is |
|---|---|
| `template/` | The files a new project starts from: configs, build scripts and test runners |
| `roblox-ts-scaffold-guide.md` | The full guide: the folder layout, why it's built this way, and the problems that cost the most time to track down |

## Setting up a new game

You'll need [Node.js](https://nodejs.org/) (24 or newer), [Git](https://git-scm.com/),
[Rokit](https://github.com/rojo-rbx/rokit) and Roblox Studio installed, and an AI coding agent such as Claude Code.

Paste this prompt to your agent:

```
Deploy https://github.com/Shadercloud/roblox-ts-scaffold as a new Roblox game project. Read its README first and follow the "Instructions for agents" section. Ask me where I want the game repo installed.
```

The agent asks you a few questions (where to put the project, the game's name, one place or two), then builds the
project and checks that it compiles and its tests pass.

Prefer to do it by hand? Follow the agent instructions below yourself: they work the same way.

## Instructions for agents

You've been asked to set up a new Roblox game project from this scaffold. Work through these steps in order.

### 1. Ask first

Ask the user, and wait for the answers:

1. **Where to install the project.** An empty folder, or one that doesn't exist yet. Don't use a folder that
   already has files in it without checking with the user.
2. **The game's name**, e.g. `Hearthstead`, and a lowercase package name with no spaces, e.g. `hearthstead`.
   Suggest the package name from the game name.
3. The questions in the **"Ask first" section of `roblox-ts-scaffold-guide.md`**: one place or two, the UI library,
   and whether they use a Studio test plugin.
4. **Whether to create a GitHub repo** for it, and if so, public or private.

### 2. Get the scaffold

Clone this repo into a temporary folder, not into the project folder:

```
git clone --depth 1 https://github.com/Shadercloud/roblox-ts-scaffold <temp folder>
```

Read `roblox-ts-scaffold-guide.md` in full before going on. It's the spec for everything below.

### 3. Create the project

1. Copy everything in `template/`, including dotfiles (`.github/`, `.gitignore`, `.prettierrc`...), into the
   project folder. Don't copy the README, guide or LICENSE of this repo.
2. Replace the placeholders in every copied file:

   | Placeholder | Replace with |
   |---|---|
   | `__GAME_NAME__` | The game's display name |
   | `__GAME_SLUG__` | The package name |

   Then search the project for `__GAME_` to make sure none are left.
3. Follow the guide to create `src/`, `tests/` and `stories/`, including one small passing test so `npm test` has
   something to run. If the user chose one place, remove the lobby files as the guide describes.
4. Run `rokit install`, then `npm install`.
5. `git init`, and make a first commit only if the user agreed to one.

Copy `scripts/lune/rbx.luau` exactly as it is. Don't rewrite or "simplify" it: it's the stand-in Roblox game tree
that lets compiled code load under Lune, and the tests depend on it. If it needs a fix, make the smallest change and
say what changed.

Keep `typescript` pinned to the exact version roblox-ts uses (`5.5.3` for roblox-ts 3.0), with no `^`, even if
npm suggests an upgrade. Gotcha 1 in the guide explains why.

### 4. Check it works

Work through the "Verify before calling it done" section at the end of the guide. At minimum,
`npm run build`, `npm test`, `npm run lint`, `npm run format:check` and `npm run typecheck` must all pass.

### 5. Hand over

Delete the temporary clone. Then tell the user:

- where the project is and what you created;
- how to start working: `npm run dev`, then connect the Rojo plugin in Studio to port 34870;
- the Studio plugins to install: [Rojo](https://rojo.space/docs/v7/getting-started/installation/), and UI Labs if they
  kept the stories;
- anything that didn't pass, with its error.

## Versions

Package versions in `template/package.json` were current on 2026-09-12. Newer ones are usually fine, except
TypeScript, which must match roblox-ts exactly.

## License

MIT. See `LICENSE`. Use it for any project, commercial or not.
