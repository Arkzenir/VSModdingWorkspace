# VS Modding Workspace

A Claude Code workspace for building Vintage Story mods on Windows. The workspace itself lives on `main` and stays clean — all mod work happens on branches or in separate repos, and the workspace resets between projects.

---

## What you need

| Tool | Why |
|---|---|
| [Git for Windows](https://git-scm.com/download/win) | Cloning API source and mod repos |
| [.NET SDK 7 or 8](https://dotnet.microsoft.com/download) | Compiling mods (`net7.0` for VS ≤1.21, `net8.0` for ≥1.22) |
| [Vintage Story](https://www.vintagestory.at/) | Game DLLs are required for compilation |
| [VS Code](https://code.visualstudio.com/) + [Claude Code](https://claude.ai/download) | The development environment |
| PowerShell 5.1 | Already built into Windows 10/11 |

---

## First-time setup

### Step 1 — Unblock and initialise

**Double-click `setup.bat`.**

This handles two things Windows blocks by default — script execution policy and the "downloaded from internet" file mark — then creates the workspace folder structure. No terminal needed.

> **If `setup.bat` fails,** open PowerShell and run these manually:
> ```powershell
> Unblock-File .\scripts\vs-workspace.ps1
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> .\scripts\vs-workspace.ps1 init
> ```

### Step 2 — Open in VS Code and install extensions

Open the workspace folder in VS Code. When prompted to install recommended extensions, accept. This gives you C# IntelliSense, PowerShell syntax support, and git graph tooling.

### Step 3 — Fetch reference sources

Run these tasks from VS Code (`Ctrl+Shift+P` → **Run Task**):

| Task | What it fetches |
|---|---|
| `WS: Fetch API Version` | vsapi source — Claude Code reads this to understand the modding API. Enter your game version, e.g. `1.21.5` |
| `WS: Fetch Game Source (Essentials)` | vsessentialsmod — vanilla core systems (player, weather, trading) |
| `WS: Fetch Game Source (Survival)` | vssurvivalmod — vanilla content (blocks, items, world gen) |

These clone from GitHub and check out the commit closest to your requested version. The vsapi and game source repos have no release tags — version matching works by searching commit history.

### Step 4 — Configure your game path

Open `workspace.json` and set `gameDirectory` to your Vintage Story install folder:

```json
"gameDirectory": "C:\\Program Files\\Vintagestory"
```

This is used when scaffolding new mods — it pre-fills `Properties\localSettings.props` with your game path so the build system can find the game DLLs.

---

## Daily workflow

### Starting a new mod

1. `Ctrl+Shift+P` → **`WS: New Mod`** → enter a PascalCase name (e.g. `GlowingMushroom`)
2. Open Claude Code
3. Type `/new-mod GlowingMushroom` — Claude Code scaffolds the project and asks what to build
4. Describe the mod — Claude Code writes the code

### Working on an existing mod

1. `Ctrl+Shift+P` → **`WS: Import Mod`** → enter a local folder path, `.zip` path, or git URL
2. The script inspects the mod's structure and sets it as the active target
3. Open Claude Code and describe what to change, fix, or add

### Building

| What | How |
|---|---|
| Debug build | `Ctrl+Shift+B` |
| Release build + distributable zip | `Ctrl+Shift+P` → `WS: Build Release` |

**Debug output** lands in `mods\YourMod\bin\Debug\{vsver}\Mods\{modid}\`. Add this `Mods\` folder to your game's ModPaths in `clientsettings.json` and asset edits are live without rebuilding — only C# changes require a recompile.

**Release output** lands in `mods\YourMod\Releases\{modid}_{version}_vs{vsver}.zip`, ready to upload to the VS mod portal.

### Ending a session

`Ctrl+Shift+P` → **`WS: Publish and Reset`**

This commits the mod source to a `mod/{modid}` branch, pushes it, and clears `workspace.json` back to its neutral state — ready for the next project. Reset only runs if Publish succeeds.

> **For a standalone repo instead of a branch:**
> `Ctrl+Shift+P` → **`WS: Export Mod (standalone repo)`** → enter a git remote URL

### Resuming work on a previously published mod

```powershell
git checkout mod/mymod
```
Then `Ctrl+Shift+P` → **`WS: Set Active Mod`** → enter the mod name.

---

## Claude Code slash commands

Type these in Claude Code to start a workflow without writing a full prompt. Arguments go after the command name.

| Command | Does |
|---|---|
| `/new-mod MyMod` | Scaffolds the project (if not already done), then asks what to build |
| `/add-feature <description>` | Adds a feature following Task Mode A — reads the API source, checks vanilla patterns, writes code |
| `/fix <description or log>` | Diagnoses and fixes a bug following Task Mode B — reads all source first, finds root cause, makes minimal change |
| `/port 1.21.5` | Ports the active mod to a different VS version — creates new csproj, fixes API breaking changes |
| `/publish` | Runs `publish-mod` then `reset`, reports what branch was saved |
| `/status` | Summarises current workspace state and session progress |

Commands are defined in `.claude/commands/` as markdown files — edit them to adjust the default workflow prompts.

---

## VS Code tasks

All workspace commands are available via `Ctrl+Shift+P` → **Run Task** → type `WS:`. Tasks that need input (mod name, version) show a native VS Code prompt box.

| Task | What it does |
|---|---|
| **`WS: Build Debug`** | Compile — also `Ctrl+Shift+B` |
| **`WS: Build Release`** | Compile + produce release zip in `Releases\` |
| **`WS: New Mod`** | Prompt for name, scaffold full project |
| **`WS: Import Mod`** | Prompt for source, import and inspect |
| **`WS: Set Active Mod`** | Switch `targetMod` in workspace.json |
| **`WS: List Mods`** | Show all mods in `mods\` |
| **`WS: Fetch API Version`** | Prompt for version, clone vsapi source |
| **`WS: Fetch Game Source (Essentials)`** | Clone vsessentialsmod |
| **`WS: Fetch Game Source (Survival)`** | Clone vssurvivalmod |
| **`WS: Publish Mod`** | Commit mod to branch and push |
| **`WS: Publish and Reset`** | Publish then reset — full end-of-session |
| **`WS: Export Mod (standalone repo)`** | Push mod to a separate git remote |
| **`WS: Reset Workspace`** | Clear targetMod, deps, examples from workspace.json |
| **`WS: Status`** | Show current workspace configuration |

### Keyboard shortcuts

`Ctrl+Shift+B` is already bound to debug build. To bind other tasks to single keystrokes:

1. Open `Ctrl+Shift+P` → **Preferences: Open Keyboard Shortcuts (JSON)**
2. Paste the contents of `.vscode/keybindings_suggested.json` inside the `[ ]`

Suggested bindings: `Ctrl+Shift+Alt+B` (release build), `Ctrl+Shift+Alt+P` (publish and reset), `Ctrl+Shift+Alt+S` (status), `Ctrl+Shift+Alt+R` (re-run last task). Adjust keys to suit.

---

## How the git workflow works

```
main branch              mod/mymod branch          standalone repo
───────────────          ─────────────────────     ───────────────
CLAUDE.md                CLAUDE.md                 source\
scripts\                 scripts\                  resources\
workspace.json (clean)   workspace.json (active)   .gitignore
.gitignore               mods\MyMod\               .git\
setup.bat                  source\
.vscode\                   resources\
.claude\                   Directory.Build.props
                           ...
```

`mods\`, `api\`, `gamesrc\`, `dependencies\`, and `examples\` are **gitignored on `main`**. They exist only as local working directories and are never committed to the main branch.

**`publish-mod`** force-adds `mods\{ModName}\` (bypassing the gitignore), commits it to `mod/{modid}`, pushes, stashes and restores any local changes, then returns you to your original branch.

**`reset`** clears only `targetMod`, `dependencies`, and `examples` from `workspace.json`. Your `gameVersion`, `apiVersion`, `dotnetTarget`, and `gameDirectory` persist — they don't change between projects.

---

## Mod project structure

Every mod scaffolded with `new-mod` follows this layout:

```
mods\MyMod\
├── .gitignore
├── Directory.Build.props          ← Edit here: mod name, id, version, description, side, authors
├── Common.Build.targets           ← Shared MSBuild logic — output paths, refs, modinfo, zip
├── MyMod_1.21.csproj              ← One file per supported VS version (thin — version + path only)
├── Properties\
│   ├── localSettings.props        ← Your machine's game install paths (gitignored)
│   └── localSettings.props.template  ← Committed template
├── source\                        ← C# source files
├── resources\
│   ├── modicon.png                ← Optional: 32×32 PNG shown in the mod manager
│   └── assets\mymod\
│       ├── blocktypes\            ← Block JSON definitions
│       ├── itemtypes\             ← Item JSON definitions
│       ├── entities\              ← Entity JSON definitions
│       ├── recipes\               ← Crafting, alloy, smithing, barrel, etc.
│       ├── worldgen\              ← World generation config
│       ├── config\                ← Mod config JSON files
│       ├── patches\               ← JSON patches to vanilla content
│       ├── lang\
│       │   └── en.json            ← Localisation strings
│       ├── textures\              ← PNG texture files
│       │   ├── block\             ← Block face textures
│       │   ├── item\              ← Item textures
│       │   ├── entity\            ← Entity skin textures
│       │   └── gui\               ← Dialog backgrounds, HUD icons
│       ├── shapes\                ← VS JSON cube-model shape files
│       │   ├── block\
│       │   ├── item\
│       │   └── entity\
│       ├── sounds\                ← OGG sound files
│       └── music\                 ← OGG music tracks
├── deps\
│   └── somedep-1.21\              ← Vendored dep DLLs per VS version (auto-referenced in build)
└── external\                      ← Ad-hoc DLLs, any version (auto-referenced in build)
```

**Things to know:**
- `modinfo.json` is **generated by MSBuild** from `Directory.Build.props` — never create or edit it directly. Change the properties in `Directory.Build.props` instead.
- `resources\assets\` is **symlinked** into the build output. Asset edits (JSON, textures, sounds) are immediately visible in-game without recompiling.
- `modicon.png` is **optional**. If present at `resources\modicon.png`, the build copies it to the output root automatically. No config needed.
- To support a second VS version, copy the `.csproj`, update `<VSVersion>` and `<TargetFramework>`, and add a `GameDirectory` entry in `localSettings.props`.

### Asset reference

| Asset type | Format | Path | Reference in JSON |
|---|---|---|---|
| Textures | PNG | `textures/block/`, `textures/item/`, `textures/entity/`, `textures/gui/` | `"texture": { "base": "block/stone/granite" }` |
| Shapes | JSON (VS format) | `shapes/block/`, `shapes/item/`, `shapes/entity/` | `"shape": { "base": "item/simplewand" }` |
| Sounds | OGG | `sounds/` | `"sounds": { "place": "block/stone" }` |
| Vanilla assets | — | — | Prefix with `game:` — e.g. `"game:block/metal/copper"` |

Shape files use VS's own JSON cube-model format, not FBX or OBJ. Author them with [Blockbench](https://www.blockbench.net/) (Vintage Story plugin) or the in-game model editor (`G` key in creative mode). Simple flat items render from their texture alone — no shape file needed.

---

## Reference sources

These are fetched once and live in gitignored local folders. Claude Code reads them automatically — they are never used for compilation.

### VS API source (`api\`)

The [vsapi](https://github.com/anegostudios/vsapi) repository contains the full C# API surface. Claude Code reads it to understand available types, interfaces, and method signatures.

```powershell
# Fetch and check out at a specific version (recommended)
.\scripts\vs-workspace.ps1 fetch-api 1.21.5

# Or manually: clone, find the commit, check out, register
git clone https://github.com/anegostudios/vsapi.git api\1.21.5\vsapi
git -C api\1.21.5\vsapi log --oneline | Select-String "1.21.5"
git -C api\1.21.5\vsapi checkout <hash>
.\scripts\vs-workspace.ps1 use-api 1.21.5

# No git: download ZIP from GitHub, extract to api\1.21.5\vsapi\, then:
.\scripts\vs-workspace.ps1 use-api 1.21.5
```

If the exact version isn't found, the closest available commit is used automatically.

### Game source repos (`gamesrc\`)

The vanilla mod sources show how the game implements its own content — the best reference for writing code that integrates with vanilla systems.

```powershell
.\scripts\vs-workspace.ps1 fetch-gamesrc essentials   # core: player, weather, trading
.\scripts\vs-workspace.ps1 fetch-gamesrc survival     # content: blocks, items, world gen
.\scripts\vs-workspace.ps1 fetch-gamesrc survival 1.21.5   # specific version
```

### Dependency mods

Dependencies come in two kinds — source context for Claude Code, and compiled DLLs for the build system. Usually you need both.

**Source context** (`dependencies\`) — Claude Code reads this to understand a dependency's public API when writing code that calls it:

```powershell
.\scriptss-workspace.ps1 add-dep https://github.com/someone/SomeMod.git
.\scriptss-workspace.ps1 add-dep C:\mods\SomeMod
```

**Build-time DLL reference** — required when your C# code calls into another mod's classes. The compiler needs the DLL to build against. Three tiers are tried in order:

1. DLLs in `$(GameDirectory)/Mods/` — automatic if the dep is installed with the game
2. DLLs in `mods\MyMod\deps\{name}-{vsver}\` — vendored fallback committed to your mod repo
3. DLLs in `mods\MyMod\external\` — ad-hoc one-offs

To populate the vendored fallback:

```powershell
# Auto-discovers from the game's Mods folder
.\scripts\vs-workspace.ps1 add-dep-dll CarryCapacity 1.21

# Explicit path
.\scripts\vs-workspace.ps1 add-dep-dll CarryCapacity 1.21 C:\path\to\CarryCapacity.dll
```

For deps that need a fully customisable install path (overrideable per machine via `localSettings.props`), ask Claude Code to add an explicit named reference — see `CLAUDE.md → Step 3` for the full pattern.

### Example mods (`examples\`)

Add source from mods that demonstrate patterns you want to follow.

```powershell
.\scripts\vs-workspace.ps1 add-example https://github.com/anegostudios/vsmodexamples.git
```

---

## workspace.json

Committed to `main` in its neutral state. The three session-specific fields (`targetMod`, `dependencies`, `examples`) are cleared by `reset` between projects.

```json
{
  "gameVersion":   "1.21.5",
  "apiVersion":    "1.21.5",
  "dotnetTarget":  "net8.0",
  "gameDirectory": "C:\\Program Files\\Vintagestory",
  "targetMod":     null,
  "dependencies":  [],
  "examples":      []
}
```

| Field | What it controls |
|---|---|
| `gameVersion` | Written into the generated `modinfo.json` as the minimum game version |
| `apiVersion` | Which `api\` subfolder Claude Code reads for type/interface context |
| `dotnetTarget` | .NET target for new mod scaffolding (`net7.0` for VS ≤1.21, `net8.0` for ≥1.22) |
| `gameDirectory` | Pre-filled into `localSettings.props` when scaffolding a new mod |
| `targetMod` | Active mod for build commands and Claude Code sessions |
| `dependencies` | Folders under `dependencies\` that Claude Code reads for context |
| `examples` | Folders under `examples\` that Claude Code studies for patterns |

---

## Full command reference

```
init                              Create workspace folder structure
status                            Show full configuration and validation

fetch-api <version>               Clone vsapi, check out closest version commit
use-api <version>                 Switch active API version in workspace.json
list-api                          List downloaded API versions

fetch-gamesrc <name> [version]    Clone game source repo (essentials | survival)
list-gamesrc                      List fetched game source repos

add-dep <path-or-url> [name]      Add dependency mod source for Claude Code context
remove-dep <name>                 Remove dependency from scope
list-deps                         List in-scope dependencies

add-dep-dll <name> <vsver> [path] Copy a dep DLL into the active mod's deps\ folder
                                    Searches game Mods folder automatically if no path given

add-example <path-or-url> [name]  Add example mod for Claude Code context
remove-example <name>             Remove example from scope
list-examples                     List in-scope examples

new-mod <ModName>                 Scaffold a new mod project
import-mod <src> [name]           Import an existing mod (folder, zip, or git URL)
use-mod <ModName>                 Set the active target mod
list-mods                         List all mods in mods\

build [debug|release]             Compile the active mod
                                    debug:   active apiVersion csproj → bin\Debug\{vsver}\Mods\
                                    release: all csproj files → Releases\{modid}_{ver}_vs{vsver}.zip

publish-mod [branch] [remote]     Commit mod to a branch and push (default: mod/{modid}, origin)
export-mod [git-url]              Initialise mod as a standalone git repo; push if URL given
reset [clean]                     Clear targetMod, dependencies, examples from workspace.json
                                    clean: also delete local api\, gamesrc\, mods\, deps\, examples\
```
