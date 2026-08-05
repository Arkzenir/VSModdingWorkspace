# Vintage Story Modding Harness

A workspace for building Vintage Story mods with any coding agent. Every mod gets its
own isolated workspace; everything downloaded is shared between them. Switching mods
is one command and re-downloads nothing.

This harness **develops** mods. It never publishes them — when a mod is ready you copy
its folder out, which is already a complete git repo, and push it wherever you like.

---

## What you need

| Tool | Why |
|---|---|
| [Git](https://git-scm.com/downloads) | Fetching API and game source; each mod is a repo |
| [.NET SDK 7 or 8](https://dotnet.microsoft.com/download) | Compiling (`net7.0` for VS ≤1.20, `net8.0` for ≥1.21) |
| [Vintage Story](https://www.vintagestory.at/) | The game DLLs are required to compile against |
| PowerShell 5.1+ | Built into Windows 10/11. On Linux/macOS install [PowerShell 7](https://github.com/PowerShell/PowerShell) |
| A coding agent | Claude Code, OpenCode, Goose, Cursor, Codex, Gemini CLI — any of them |

---

## Setup

**Windows:** double-click `setup.bat`.
**Anywhere else:** `pwsh ./setup.ps1`

That unblocks the scripts, checks your prerequisites, creates `harness.json`, and
builds the folder structure. Then:

1. Edit `harness.json` and set `gameDirectory` to your Vintage Story install.
2. Download the reference sources once — they are shared by every mod you ever make:

```powershell
.\scripts\vsmod.ps1 fetch-api 1.21.5
.\scripts\vsmod.ps1 fetch-gamesrc essentials
.\scripts\vsmod.ps1 fetch-gamesrc survival
```

3. Open your agent in this folder. It picks up `AGENTS.md` on its own.

---

## Daily use

### Start a new mod

```powershell
.\scripts\vsmod.ps1 new GlowingMushroom
```

Creates `workspaces/GlowingMushroom/`, scaffolds the project, and initialises
`mod/` as a git repo with an initial commit on `main`. Then tell your agent what to
build, or run its `/new-mod` command.

### Bring in an existing mod

```powershell
.\scripts\vsmod.ps1 import https://github.com/someone/TheirMod.git
.\scripts\vsmod.ps1 import C:\dev\MyOldMod
.\scripts\vsmod.ps1 import C:\downloads\SomeMod.zip
```

Same result as `new`: a workspace with a git-backed `mod/` folder, made active. Git
history is preserved when there is any, so a fork stays a fork. When there is none, a
repo is initialised. The importer reports the mod's id, version, build system and
layout so your agent knows what it is dealing with.

### Switch between mods

```powershell
.\scripts\vsmod.ps1 list
.\scripts\vsmod.ps1 use AnotherMod
```

Instant. Nothing is downloaded, copied, moved or reconfigured — the API source, game
source, dependencies and examples are shared from `cache/` and simply relinked.

### Build

```powershell
.\scripts\vsmod.ps1 build            # debug
.\scripts\vsmod.ps1 build release    # release + distributable zip
```

**Debug** lands in `mod/bin/Debug/{vsver}/Mods/{modid}/`. Add the `Mods/` folder above
it to your game's ModPaths in `clientsettings.json` and asset edits go live without
rebuilding — only C# changes need a recompile.

**Release** lands in `mod/Releases/{modid}_{version}_vs{vsver}.zip`, ready for the
mod portal.

### Publish (by hand, deliberately)

```powershell
.\scripts\vsmod.ps1 export
```

Copies the mod repo to `exports/{Name}/`, minus build output and your local settings.
It is a complete git repo with full history and no remote. Publish it yourself:

```powershell
cd exports\GlowingMushroom
git remote add origin https://github.com/you/glowing-mushroom.git
git push -u origin main
```

Nothing in this harness ever pushes, adds a remote, or opens a PR, and `AGENTS.md`
instructs agents not to either. Local commits inside `mod/` are fine and encouraged.

---

## How it is laid out

```
harness-root/
├── AGENTS.md                  Instructions for every agent  <- the real one
├── CLAUDE.md, GEMINI.md,      Pointers to AGENTS.md, for agents that
│   .goosehints, .cursorrules,   look for their own filename
│   .windsurfrules, .github/copilot-instructions.md
├── harness.json               Your machine settings + which workspace is active
├── scripts/vsmod.ps1          The whole CLI
├── prompts/                   Reusable task prompts (agent-neutral)
├── cache/                     Downloaded ONCE, shared by every workspace
│   ├── api/{version}/vsapi/
│   ├── gamesrc/{name}/
│   ├── dependencies/{name}/
│   └── examples/{name}/
└── workspaces/
    ├── GlowingMushroom/
    │   ├── workspace.json     This mod's own settings
    │   ├── mod/               THE MOD — a standalone git repo
    │   ├── api/           →   link into cache/api/1.21.5
    │   ├── gamesrc/       →   links into cache/gamesrc
    │   ├── dependencies/  →   links into cache/dependencies
    │   └── examples/      →   links into cache/examples
    └── AnotherMod/            Fully independent — its own API version, deps, examples
```

`api/`, `gamesrc/`, `dependencies/` and `examples/` are directory junctions on Windows
and symlinks elsewhere. Junctions were chosen deliberately: unlike symlinks they need
no administrator rights and no developer mode.

The consequence worth understanding: **two workspaces can target different game
versions at the same time.** One mod on 1.20.4 and another on 1.21.5 coexist happily,
each pointing at its own cached API source, with a single copy of each on disk.

### Config split

`harness.json` holds what belongs to your machine:

```json
{
  "gameDirectory": "C:\\Program Files\\Vintagestory",
  "author": "Author",
  "exportDirectory": "",
  "defaults": { "gameVersion": "1.21.5", "apiVersion": "1.21.5", "dotnetTarget": "net8.0" },
  "activeWorkspace": "GlowingMushroom"
}
```

`workspaces/{Name}/workspace.json` holds what belongs to that mod — `modName`, `modId`,
`modVersion`, `gameVersion`, `apiVersion`, `dotnetTarget`, plus its `dependencies`,
`examples` and `gamesrc` lists. Its `gameDirectory` is an optional override; leave it
empty to inherit from `harness.json`.

`defaults` seeds new workspaces only. Changing it never disturbs existing mods.

---

## Agent support

`AGENTS.md` is the single source of truth. It is [the cross-tool open
standard](https://agents.md/), read natively by OpenCode, Goose, Codex, Cursor, Jules
and others. Every other instruction file here is a short pointer back to it rather than
a copy, because duplicated instructions drift apart and start contradicting each other.

If your agent reads some other filename, add a pointer file of your own — three lines
saying "read AGENTS.md" is all it needs.

### Task prompts

`prompts/` holds plain-markdown task prompts usable with any agent: paste one in, or
invoke it through your agent's command system.

| Prompt | Purpose |
|---|---|
| `new-mod.md` | Scaffold a mod and start building it |
| `import-mod.md` | Import an existing mod and understand it before changing it |
| `add-feature.md` | Add a feature, reading the API and vanilla source first |
| `fix.md` | Diagnose a bug from a log, fix it minimally |
| `port.md` | Port to another game version, finding breaking changes |
| `switch.md` | Change workspace and re-orient |
| `status.md` | Summarise the session |

Launchers are pre-wired for Claude Code (`.claude/commands/`) and OpenCode
(`.opencode/command/`), both supporting `$ARGUMENTS`:

```
/new-mod GlowingMushroom
/fix the block disappears when placed on slabs
/port 1.22.0
```

They are deliberately thin — each says "read `prompts/X.md` and do that". Edit the
prompt, and every agent picks the change up.

---

## Reference sources

Fetched once into `cache/`, linked into whichever workspaces want them, never used for
compilation — they exist so your agent can read real code instead of guessing.

```powershell
.\scripts\vsmod.ps1 fetch-api 1.21.5              # vsapi source
.\scripts\vsmod.ps1 fetch-gamesrc essentials      # core systems
.\scripts\vsmod.ps1 fetch-gamesrc survival        # blocks, items, world gen
.\scripts\vsmod.ps1 fetch-gamesrc creative
.\scripts\vsmod.ps1 add-dep https://github.com/someone/SomeMod.git
.\scripts\vsmod.ps1 add-example https://github.com/anegostudios/vsmodexamples.git
```

Neither vsapi nor the game source repos carry release tags, so the matching commit is
found by searching history. If an exact version is not found, the closest one is used
and reported.

### Building against a dependency

Reading a dependency's source is not enough to *call* it — the compiler needs its DLL.
Three tiers are tried in order:

1. `$(GameDirectory)/Mods/*.dll` — automatic if the dep is installed with the game.
2. `mod/deps/{name}-{vsver}/*.dll` — vendored, committed, travels with the repo.
3. `mod/external/*.dll` — ad-hoc.

Populate tier 2 with:

```powershell
.\scripts\vsmod.ps1 add-dep-dll CarryCapacity 1.21
.\scripts\vsmod.ps1 add-dep-dll CarryCapacity 1.21 C:\path\to\CarryCapacity.dll
```

---

## Command reference

```
Switching
  use <Name>                       Make a workspace active — the one command you need
  list                             List every workspace
  status                           Active workspace in detail, incl. link health
  sync                             Rebuild this workspace's links from its manifest
  remove <Name>                    Delete a workspace (asks for confirmation)

Starting work
  new <ModName>                    Scaffold a new mod; mod/ becomes a git repo
  import <src> [Name]              Import a folder, .zip or git URL
  git-init                         Turn an imported folder into a git repo

Building and handing off
  build [debug|release]            Compile the active mod
  export [path]                    Copy the mod repo out for you to push

Shared cache
  fetch-api <version>              Cache vsapi source and link it in
  use-api <version>                Point this workspace at another cached version
  list-api                         List cached API versions
  fetch-gamesrc <name> [ver]       essentials | survival | creative
  list-gamesrc                     List cached game source
  cache [list|remove <kind>/<name>]  Inspect or prune the cache

Per-workspace context
  add-dep <path-or-url> [name]     Dependency source, for the agent to read
  remove-dep <name>                Unlink it (cached copy stays)
  list-deps                        List this workspace's dependencies
  add-example <path-or-url> [name] Example mod source
  remove-example <name>            Unlink it
  list-examples                    List this workspace's examples
  add-dep-dll <name> <vsver> [dll] Vendor a dependency DLL into mod/deps/

Setup
  init                             Create cache/ and workspaces/, check config
  help                             This list
```

---

## Mod project structure

Every scaffolded mod:

```
mod/
├── .git/                          Already a repo. Commit freely; push by hand.
├── .gitignore
├── README.md
├── Directory.Build.props          Mod identity — edit name, id, version, side, authors
├── Common.Build.targets           Shared build logic
├── MyMod_1.21.5.csproj            One per supported game version
├── Properties/
│   ├── localSettings.props        Your game paths (gitignored)
│   └── localSettings.props.template
├── source/                        C# source
├── resources/
│   ├── modicon.png                Optional 32×32, copied to output automatically
│   └── assets/{modid}/
│       ├── blocktypes/ itemtypes/ entities/ recipes/ worldgen/ config/ patches/
│       ├── lang/en.json
│       ├── textures/{block,item,entity,gui}/
│       ├── shapes/{block,item,entity}/
│       └── sounds/ music/
├── deps/{name}-{vsver}/           Vendored dependency DLLs
└── external/                      Ad-hoc DLLs, auto-referenced
```

Three things to know:

- **`modinfo.json` is generated by MSBuild** from `Directory.Build.props`. Never write
  one by hand — edit the properties instead.
- **Assets are symlinked** into the build output, so JSON, texture and sound edits are
  live in-game without rebuilding.
- **To support another game version**, copy the `.csproj`, update `<VSVersion>` and
  `<TargetFramework>`, and add a `GameDirectory_X_XX` entry to `localSettings.props`.

### Asset reference

| Type | Format | Referenced as |
|---|---|---|
| Textures | PNG | `"texture": { "base": "block/stone/granite" }` |
| Shapes | VS JSON cube-model | `"shape": { "base": "item/simplewand" }` |
| Sounds | OGG | `"sounds": { "place": "block/stone" }` |
| Vanilla anything | — | prefix `game:` — `"game:block/metal/copper"` |

Shapes use Vintage Story's own JSON format, not FBX or OBJ. Author them in
[Blockbench](https://www.blockbench.net/) with the VS plugin, or the in-game editor
(`G` in creative). Flat items render from their texture alone and need no shape file.

---

## Automation

There are no editor tasks and no IDE plugin. Everything is `scripts/vsmod.ps1`, so it
works from a terminal, an agent's shell tool, a file watcher, or a daemon:

```powershell
pwsh -NoProfile -File scripts/vsmod.ps1 build release
```

Commands are non-interactive except `remove` and `cache remove`, which ask for typed
confirmation before deleting anything.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `status` shows `x api/ (not cached)` | Run the `fetch-api` command it prints |
| A link is missing after moving the harness | Run `sync` — junctions store absolute paths |
| Build fails on missing game DLLs | `gameDirectory` in `harness.json`, or the mod's `Properties/localSettings.props`, points at the wrong install |
| `new` refuses a mod name | Names become C# namespaces: letters and digits only, starting with a letter |
| Initial commit did not happen | Git has no identity yet. Set `user.name` and `user.email`, then run `git-init` |
| Scripts blocked on Windows | Re-run `setup.bat`, or `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |

---

## Licence

See `LICENSE`. Mods you create are yours; add your own licence to each exported repo.
