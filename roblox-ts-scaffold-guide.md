# Scaffolding a roblox-ts game project

Instructions for an agent setting up a new Roblox game repo with the same foundation as
Hearthstead: roblox-ts + Rojo + Flamework + React, tests that run both headlessly and in Studio,
and CI. Nothing here is Hearthstead-specific.

It is written to be handed to an agent on its own, in an empty repo. Follow it in order. Most of
its value is the [Gotchas](#gotchas) — every one cost real debugging time, and several are
invisible until late.

**Copy from `template/` (alongside this guide) wherever it fits** rather than regenerating: it
holds the working configs, both test runners and the virtual DataModel. Replace `__GAME_NAME__`
and `__GAME_SLUG__` throughout. See `README.md` for what is and isn't included.

## Ask first

Four things change what you build. Ask, don't assume:

1. **Game name**, and the npm package name.
2. **How many places?** One (most games), or two — e.g. a lobby that teleports into a world. This
   guide assumes two, named `game` and `lobby`; with one place, drop every `lobby` row and the
   `common` layer folds into it.
3. **UI library.** This guide assumes `@rbxts/react` plus a component library. If there isn't one,
   drop the component library and the stories tree, and keep plain React.
4. **Does the owner have a Studio plugin for running tests** (e.g. Lunit Test Companion)? It
   changes only convenience, not the layout.

## What you are producing

- Two shipping places that build and publish, plus **one dev place** that is the only thing
  connected to Studio day to day.
- A pure domain layer that is enforced pure by lint, so its tests run headlessly.
- Tests and stories in their own top-level trees, absent from shipping places by construction.
- `npm test` running the real compiled Luau headlessly under Lune.
- CI running build, typecheck, lint, format and tests on every push.

## Stack

Pin these. The versions matter where noted.

| Area | Choice | Notes |
|---|---|---|
| Language | **roblox-ts 3.x** | Compiles with its **own** bundled TypeScript |
| TypeScript | **Exactly the version roblox-ts bundles** (3.0.0 → `5.5.3`) | Pin exact, not `^`. See [Gotchas](#1-pin-typescript-to-the-version-roblox-ts-bundles) |
| Types | `@rbxts/types`, `@rbxts/compiler-types`, `@rbxts/services` | |
| Sync | **Rojo 7.x** | Three project files; see [Places](#places) |
| Toolchain | **Rokit** (`rokit.toml`) | Pins Rojo and Lune for every machine and CI |
| Framework / DI | **Flamework** (`core`, `networking`, `components`) + `rbxts-transformer-flamework` | DI makes services swappable in tests; networking generates runtime type guards |
| State | **Charm** + **charm-sync** (+ `@rbxts/react-charm`) | Server-authoritative state replicated as small patches |
| UI | `@rbxts/react` + `@rbxts/react-roblox` + a component library | |
| Stories | `@rbxts/ui-labs` | Needs the UI-Labs **Studio plugin** installed separately |
| Tests | `@rbxts/lunit` | Decorator-based; `@Tag("Studio")` / `@Tag("Lune")` |
| Headless runtime | **Lune** | Runs the real compiled Luau; see [The headless runner](#the-headless-runner) |
| Lint / format | **ESLint 10** (flat config) + `typescript-eslint` + `eslint-plugin-roblox-ts`, **Prettier 3** | Add `@eslint/js` as a direct devDependency |
| CI | GitHub Actions | |
| Runtime | Node 24 + npm | |

## Repo layout

```
├── game.project.json / lobby.project.json   # Shipping places: publish + CI only
├── dev.project.json                         # THE place connected in Studio day to day
├── tools.project.json                       # Where compiled command-line tools sit
├── tsconfig.json                            # Shared base + editor/ESLint view
├── tsconfig.game.json / tsconfig.lobby.json # Per shipping place
├── tsconfig.dev.json                        # src + tests + stories -> out-dev/
├── tsconfig.tools.json                      # tools/ + the src it imports -> out-tools/
├── rokit.toml
├── eslint.config.mjs / .prettierrc / .editorconfig / .gitattributes
├── .github/workflows/ci.yml
├── scripts/
│   ├── test.luau                 # Headless runner (npm test)
│   ├── tool.luau                 # Runs a compiled tool
│   ├── lunit-tags.luau           # Studio/Lune tag rules, shared by both runners
│   ├── lune/rbx.luau             # Virtual DataModel from a Rojo project
│   └── studio/run-tests.server.luau
├── src/
│   ├── common/{shared,server,client}/   # Used by BOTH places
│   ├── game/
│   │   ├── shared/{domain,content,net}/ # domain = PURE game logic
│   │   ├── server/                      # services: validate, run domain, persist, replicate
│   │   └── client/                      # controllers, rendering, input, UI
│   └── lobby/{shared,server,client}/
├── tests/                        # Mirrors src/ exactly. Never inside src/
├── stories/                      # Mirrors src/ exactly
└── tools/                        # Command-line tools (roblox-ts -> Luau, run with Lune)
```

### Folder to container mapping

The folder name decides the Roblox container. **`tests/` and `stories/` obey the same rule** — this
is load-bearing, not cosmetic (see [Gotcha 3](#3-you-cannot-import-into-an-isolated-container)).

| Source | Game place | Lobby place |
|---|---|---|
| `<root>/common/shared` | `ReplicatedStorage/Common` | `ReplicatedStorage/Common` |
| `<root>/common/server` | `ServerScriptService/Common` | `ServerScriptService/Common` |
| `<root>/common/client` | `StarterPlayerScripts/Common` | `StarterPlayerScripts/Common` |
| `<root>/game/*` | its container `/Game` | — |
| `<root>/lobby/*` | — | its container `/Lobby` |

In the dev place, `tests/` mounts under a `Tests` folder in each container and `stories/` under
`Stories`, e.g. `tests/game/client` → `StarterPlayerScripts/Tests/Game`.

## Places

Three Rojo projects, only one of which is for daily work:

| Project | Contents | Connected in Studio? |
|---|---|---|
| `dev.project.json` | Both places' code, every test and story, the Studio test runner, **and the game's entry scripts** so it can be played | **Yes** — the one window |
| `lobby.project.json` | The real lobby place | Only for lobby work |
| `game.project.json` | The real game place | No — build/publish only |

Two rules that follow:

- The dev place carries the lobby's *modules* but **not** its entry scripts. Each `main.server`
  calls `Flamework.ignite()`, and two igniters in one place conflict. Exclude them with
  `globIgnorePaths` (`out-dev/src/lobby/**/*.server.luau` and `**/*.client.luau`).
- Because the dev place holds tests and both places' code, it is never what ships.

Use `{ "optional": "..." }` for every `$path` into build output — rbxtsc doesn't create output
folders that have no source files, and Rojo errors on a missing path.

## Build

`package.json` scripts:

```
build       = build:game && build:lobby && build:dev && build:tools
build:game  = rbxtsc -p tsconfig.game.json  --rojo game.project.json
build:lobby = rbxtsc -p tsconfig.lobby.json --rojo lobby.project.json
build:dev   = rbxtsc -p tsconfig.dev.json   --rojo dev.project.json
build:tools = rbxtsc -p tsconfig.tools.json --rojo tools.project.json
dev         = concurrently  <rbxtsc -w on tsconfig.dev.json>  <rojo serve dev.project.json --port 34870>
dev:lobby   = concurrently  <rbxtsc -w on tsconfig.lobby.json> <rojo serve lobby.project.json --port 34871>
serve:dev   = rojo serve dev.project.json --port 34870
test        = npm run build && lune run scripts/test.luau
lint        = eslint src tests stories tools
typecheck   = tsc --noEmit over each tsconfig
```

Each place compiles against **its own** Rojo project, so a game file importing lobby code fails
the build with "Could not find Rojo data" — the layout rule is enforced by the compiler, not by
convention.

`tsconfig.json` is the shared base and the editor/ESLint view: `rootDir: null` with
`rootDirs: ["src", "tests", "stories"]`, and `include` covering all three. The shipping configs
override `rootDir: "src"`, `rootDirs: null`. `tsconfig.dev.json` and `tsconfig.tools.json` keep
`rootDirs` and use their own `outDir` (`out-dev`, `out-tools`).

## Testing

Tests live in `tests/`, mirroring `src/`, one class per file, `export = ClassName`.
Imports reach their subject by relative path into `src/`.

| Tag | Runs | For |
|---|---|---|
| (none) | Lune and Studio | Pure logic: domain, content, codecs |
| `@Tag("Studio")` | Studio only | Anything needing the engine: Instances, services, React mounting |
| `@Tag("Lune")` | Lune only | Rare |

### The headless runner

**This is the part you cannot skip or shortcut.** roblox-ts compiles a *game* project so that every
module resolves its imports through the DataModel:

```lua
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _x = TS.import(script, game:GetService("ReplicatedStorage"), "Game", "domain", "thing")
```

A *package* build instead emits `local TS = _G[script]` with relative requires. So any test runner
that loads compiled `.luau` by file path — including Lunit's own bundled `scripts/lunit.luau` —
works for libraries and fails on the **first line of every module** of a game project with
`attempt to index nil with 'GetService'`.

So `scripts/lune/rbx.luau` builds a virtual, read-only DataModel from the same Rojo project Studio
syncs. It must:

1. Parse the Rojo project file: `$className`, `$path`, `$properties`, nested children,
   `{ "optional": … }` paths, `globIgnorePaths`, and a nested `default.project.json` inside a path.
2. Map files to instances: `init.luau` becomes its folder's own ModuleScript, `*.server.luau` →
   `Script`, `*.client.luau` → `LocalScript`, `*.luau` → `ModuleScript`.
3. Provide `game`, `GetService`, `WaitForChild`, `FindFirstChild`, `GetChildren`, `GetFullName`,
   `IsA`, and `script` inside each module.
4. Load the **real** `include/RuntimeLib.lua` (and `Promise.lua`) on top, so `TS.import` behaves
   exactly as in Studio. Do not reimplement `TS.import`.
5. Support require-by-string (`./`, `../`, `@self/`) — Charm and others need it.
6. Inject Roblox datatypes from `@lune/roblox` as globals (`Vector3`, `Vector3int16`, `CFrame`,
   `Color3`, `UDim2`, `Enum`, …). These behave like the engine's, including float32 `Vector3`.
7. Expose **no** engine: no Instances, no real services, no scheduler, no clocks. Make
   `game:GetService("Players")` an empty stub so a module merely referencing it still loads.

**Copy `template/scripts/lune/rbx.luau` (~525 lines) and `template/scripts/test.luau` (~110 lines)
rather than writing your own.** This is the hardest piece to rebuild from a description, and it is
what makes headless tests possible at all. The list above is there so you can verify or repair it,
not so you can reimplement it from scratch.

This is also what makes the domain-purity rule pay off: pure modules may use datatypes and
`buffer`, but nothing from the engine, which is exactly what Lune can provide.

### Studio tests

`scripts/studio/run-tests.server.luau` walks the place for `*.test` / `*.spec` ModuleScripts, skips
`Lune`-tagged ones and prints results. Make it **opt-in** behind an attribute
(e.g. `RunLunitTests` on `ServerScriptService`) — the dev place also plays the game, and pressing
Play should play, not run the suite.

Keep this runner even with a Studio test plugin. A plugin typically runs tests in an isolated
snapshot with no player, character or replication, so it cannot cover anything needing a running
game — a 2-player client/server test, for instance.

## Lint

Flat config (`eslint.config.mjs`). Beyond the recommended sets, the rule that earns its keep:

```js
{
  // Pure domain logic never touches Roblox services, Instances or the scheduler.
  // That is what lets its tests run headlessly.
  files: ["src/game/shared/domain/**/*.ts", "tests/game/shared/domain/**/*.ts"],
  rules: {
    "no-restricted-imports": ["error", { patterns: [
      { group: ["@rbxts/*", "!@rbxts/lunit", "@flamework/*"], message: "domain is pure: no Roblox packages, services, UI or Flamework." },
      { group: ["**/server/**", "**/client/**", "**/net/**"], message: "domain must not depend on server, client or networking code." },
    ]}],
    "no-restricted-globals": ["error", /* game, workspace, script, Instance, task, wait, delay, spawn, tick, time, os */],
  },
}
```

Apply it to the domain's **tests** as well, or they drift out of headless-runnable.
After any ESLint upgrade, verify this rule still fires — write a throwaway file that violates it
and confirm the errors, rather than trusting a clean run.

## CI

One workflow on push to `main`: checkout, Node 24, cache `node_modules` keyed on
`package-lock.json`, install Rojo and Lune from `rokit.toml`, then `npm run build`, `rojo build`
each place, `typecheck`, `lint`, `format:check`, and `lune run scripts/test.luau`.

To stay inside free minutes on a private repo: `paths-ignore` for `**/*.md` and docs folders,
`concurrency` with `cancel-in-progress`, and a `timeout-minutes`. Run the Lune script directly
rather than `npm test`, which would rebuild what the build step just built.

## Gotchas

Each of these is a real failure that is hard to diagnose from its symptom.

### 1. Pin TypeScript to the version roblox-ts bundles

roblox-ts compiles with **its own** TypeScript regardless of what the repo installs. A newer repo
TypeScript means `typecheck` and ESLint accept syntax the build rejects, and the Flamework
transformer warns on every build. Pin the exact version (`"typescript": "5.5.3"`, no caret) —
roblox-ts pins it exactly too, so a caret silently reintroduces the split.

Consequences to expect and not "fix":

- `skipLibCheck: true` is needed because `@rbxts/types` has declaration errors of its own.
- A newer TypeScript in the editor will flag `downlevelIteration` and `moduleResolution: "Node"` as
  deprecated and suggest `"ignoreDeprecations"`. **Don't.** Both are required by roblox-ts, and the
  pinned compiler rejects that value outright (`error TS5103`), breaking the build.
- Point the editor at the workspace TypeScript (`typescript.tsdk` plus
  `typescript.enablePromptUseWorkspaceTsdk`, then *Use Workspace Version*), or the editor
  type-checks with its own copy and you are back to the split.

### 2. `rootDir: "."` makes rbxtsc copy the whole repo

roblox-ts copies non-script files from `rootDir` into `outDir`. With `rootDir: "."` it tries to
copy the repo into its own output and dies with *"Cannot copy … to a subdirectory of itself"*.

Use `rootDir: null` with `rootDirs: [...]` instead when a build spans several source roots. Note
`rootDirs` does **not** merge the output: sources keep their own subfolders (`out-dev/src/…`,
`out-dev/tests/…`), so plan Rojo paths around that.

### 3. You cannot import *into* an isolated container

`StarterPlayerScripts`, `StarterGui` and friends are cloned per player at runtime, so roblox-ts
rejects an import from outside them: *"Attempted to import a file inside of an isolated container
from outside!"*

This is why `tests/` and `stories/` must mirror `src/`'s layer folders rather than living in one
place: a test of client code has to sit in `tests/<place>/client/`, or it cannot import the screen
it renders. Decide this before writing tests; discovering it later is a restructure.

### 4. Rojo reads the project file once, at startup

After editing a `.project.json`, restart the server. **Also restart after adding the first file to
a source folder that did not exist yet** — `{ "optional": … }` paths missing at startup are skipped
and not picked up later.

Symptom: `Infinite yield possible on 'X:WaitForChild("Y")'` for a module that is plainly present.
Diagnose by comparing against `rojo build <project> -o /tmp/check.rbxl`: if the module is in the
built place, the running server is stale.

### 5. Studio plugins can claim your ports

A test-runner plugin may scan a port range for its editor counterpart (Lunit's scans
**34873–34892**). Pick Rojo ports outside any such range — e.g. 34870/34871 — and write down why,
or someone will move them back.

### 6. Isolation snapshots are fussy about ancestors

A Studio test plugin that snapshots modules may only accept `Folder`, `ModuleScript` and service
ancestors. A ModuleScript nested under a `Script` — ordinary Roblox — can abort the entire run,
even when no test references it. Keep helper modules as *siblings* of scripts, not children.

### 7. Library story helpers inject controls you may not want

A component library's `createStory` helper may always add a Theme picker, merging its own controls
last so it cannot be overridden. If the game ships one theme, write your own helper wrapping
UI-Labs' `CreateReactStory` in that theme, and put it under `stories/common/client/` so it lands in
the same container as the stories. Declare the theme once in `src/common/client/` and have both the
UI controller and the story helper import it.

### 8. Smaller ones

- `@eslint/js` must be a direct devDependency: ESLint 10 stopped providing it transitively, and
  a flat config importing it fails with `ERR_MODULE_NOT_FOUND`.
- Flamework cannot generate a guard for complex conditional types (charm-sync's `SyncPayload`
  resolves to `never`). Give the event a plain wire type and cast on both ends; that is safe for
  server → client, which is trusted.
- `new Map(otherMap)` doesn't compile; copy with `forEach`. Some identifiers are compiler-reserved.
- Builds are not incremental when two configs share an `outDir`: each rbxtsc run prunes the
  other's `.tsbuildinfo`.
- Uninstall Aftman, or make sure Rokit's shims come first on `PATH`, or Aftman's `rojo` wins.
- The UI-Labs **Studio plugin** is separate from the npm package. Installing `@rbxts/ui-labs` gives
  you the authoring half only.

## Verify before calling it done

Build a place and inspect it, rather than trusting the config:

1. `npm run build`, `npm test`, `npm run lint`, `npm run format:check`, `npm run typecheck` pass.
2. `npm test` exits **non-zero** when a test fails — check with a deliberately failing test.
3. `rojo build` each project, then walk the `.rbxl` (Lune's `@lune/roblox` can deserialize it) and
   confirm: shipping places contain **no** `*.test` / `*.story` modules; the dev place contains the
   tests, the stories, and the game's entry scripts but not the lobby's.
4. In Studio on the dev place: Play boots the game, and the Studio-tagged tests pass.
5. A file importing a Roblox service inside the domain folder fails `npm run lint`.
6. A game file importing lobby code fails `npm run build`.
7. CI is green on a real push.
