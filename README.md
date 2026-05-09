# VS Modding Workspace

A Claude Code workspace for building and iterating on Vintage Story mods. The tool lives on `main` — mod work lives on branches or in separate repos.

---

## What you need

| | |
|---|---|
| [Git for Windows](https://git-scm.com/download/win) | Cloning repos |
| [.NET SDK 7 or 8](https://dotnet.microsoft.com/download) | Compiling mods |
| [Vintage Story](https://www.vintagestory.at/) | Game DLLs for building |
| [VS Code](https://code.visualstudio.com/) + Claude Code | The agent environment |
| PowerShell 5.1 | Built into Windows 10/11 — already there |

---

## First-time setup

**Double-click `setup.bat`.** It handles everything Windows blocks by default (script signing, execution policy) and creates the workspace folder structure. No terminal needed.

After it finishes, open the folder in VS Code. When prompted, install the recommended extensions — this gives you C# IntelliSense, PowerShell support, and git tooling.

Then run these three tasks from VS Code (`Ctrl+Shift+P` → **Run Task**):

1. **`WS: Fetch API Version`** — enter your game version (e.g. `1.21.5`)
2. **`WS: Fetch Game Source (Essentials)`**
3. **`WS: Fetch Game Source (Survival)`**

Finally, open `workspace.json` and set `gameDirectory` to your Vintage Story install path.

> **If `setup.bat` fails:** open PowerShell and run:
> ```powershell
> Unblock-File .\scripts\vs-workspace.ps1
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

---

## Daily workflow

### Starting a new mod

1. `Ctrl+Shift+P` → **`WS: New Mod`** → enter a name
2. Open Claude Code and type: `/new-mod YourModName`
3. Describe what the mod should do — Claude Code builds it

### Working on an existing mod

1. `Ctrl+Shift+P` → **`WS: Import Mod`** → enter a folder path, zip path, or git URL
2. Open Claude Code and describe what needs to change or be fixed

### Building and testing

| Action | How |
|---|---|
| Debug build | `Ctrl+Shift+B` |
| Release build (produces zip) | `Ctrl+Shift+P` → `WS: Build Release` |

The debug build output lands in `mods\YourMod\bin\Debug\{vsver}\Mods\`. Point your game's mod path there and asset changes are live without rebuilding — only C# changes need a recompile.

### End of session

`Ctrl+Shift+P` → **`WS: Publish and Reset`**

This commits your mod source to a `mod/{modid}` branch, pushes it, and returns the workspace to a clean state — ready for the next project.

> **Want a standalone repo instead?**
> `Ctrl+Shift+P` → **`WS: Export Mod (standalone repo)`** → enter a git remote URL

---

## Claude Code slash commands

Type these directly in Claude Code to start a workflow without writing a prompt:

| Command | What it does |
|---|---|
| `/new-mod MyMod` | Scaffolds the project, then asks what to build |
| `/add-feature <description>` | Implements a feature following the workspace conventions |
| `/fix <description or log>` | Diagnoses and fixes a bug |
| `/port 1.21.5` | Ports the mod to a different VS version |
| `/publish` | Runs publish + reset and reports what was saved |
| `/status` | Summarises the current session state |

---

## VS Code tasks

Every workspace command is available via `Ctrl+Shift+P` → **Run Task** → type `WS:`.

| Task | What it does |
|---|---|
| `WS: Build Debug` | Compile (also `Ctrl+Shift+B`) |
| `WS: Build Release` | Compile + produce distributable zip |
| `WS: New Mod` | Prompt for name, scaffold full project |
| `WS: Import Mod` | Prompt for source, import and inspect |
| `WS: Fetch API Version` | Prompt for version, clone vsapi source |
| `WS: Fetch Game Source (Essentials)` | Clone vsessentialsmod |
| `WS: Fetch Game Source (Survival)` | Clone vssurvivalmod |
| `WS: Publish and Reset` | Push mod to branch + reset workspace |
| `WS: Export Mod (standalone repo)` | Push mod to a separate git remote |
| `WS: Reset Workspace` | Clear workspace.json to neutral state |
| `WS: Status` | Show current workspace configuration |

---

## How the git workflow works

```
main branch          mod/mymod branch       standalone repo
─────────────        ──────────────────     ───────────────
CLAUDE.md            CLAUDE.md              source\
scripts\             scripts\               resources\
workspace.json       workspace.json         modinfo.json
.gitignore           mods\MyMod\            .git\
                       source\
                       resources\
                       modinfo.json
```

`mods\`, `api\`, `gamesrc\`, `dependencies\`, and `examples\` are all gitignored on `main`. They exist only as local working directories.

**`publish-mod`** force-adds `mods\{ModName}\` (bypassing the gitignore), commits it to a `mod/{modid}` branch, pushes, and returns you to `main`.

**`reset`** clears `targetMod`, `dependencies`, and `examples` in `workspace.json` — the fields that change per project. Game version, API version, and your game directory are left alone.

To resume work on a previously published mod:
```powershell
git checkout mod/mymod
.\scripts\vs-workspace.ps1 use-mod MyModName
```

---

## Mod project structure

Every mod scaffolded with `new-mod` follows this layout:

```
mods\MyMod\
├── Directory.Build.props        ← Mod identity: name, version, description, side, authors
├── Common.Build.targets         ← Shared build logic (output, references, packaging)
├── MyMod_1.21.csproj            ← One per supported VS version (thin — just version + path)
├── Properties\
│   ├── localSettings.props      ← Your local game install paths (gitignored)
│   └── localSettings.props.template  ← Committed template
├── source\                      ← C# source files
├── resources\
│   └── assets\mymod\            ← JSON assets (symlinked live into build output)
├── deps\
│   └── somedep-1.21\            ← Vendored dep DLLs, per VS version (auto-referenced)
└── external\                    ← Ad-hoc DLLs (auto-referenced, any version)
```

**Key points:**
- `modinfo.json` is **generated** from `Directory.Build.props` — never edit it directly
- Asset changes are live in-game without rebuilding (symlink)
- Release zips land in `mods\MyMod\Releases\{modid}_{version}_vs{vsver}.zip`
- Add another supported VS version by duplicating the `.csproj` and updating `<VSVersion>`

---

## Adding references

### VS API source (for Claude Code context)

The `api\` folder is read by Claude Code to understand types and interfaces. It is **not** used for compilation — that uses DLLs from your game install.

```powershell
# Automatic (recommended)
.\scripts\vs-workspace.ps1 fetch-api 1.21.5

# Manual: clone, find the version commit, check it out, then register
git clone https://github.com/anegostudios/vsapi.git api\1.21.5\vsapi
git -C api\1.21.5\vsapi log --oneline | Select-String "1.21.5"   # find the hash
git -C api\1.21.5\vsapi checkout <hash>
.\scripts\vs-workspace.ps1 use-api 1.21.5

# No git: download ZIP from github.com/anegostudios/vsapi, extract to api\1.21.5\vsapi\, then:
.\scripts\vs-workspace.ps1 use-api 1.21.5
```

> The vsapi repo has no release tags — version commits are found by searching commit messages.

### Game source repos (for vanilla pattern reference)

```powershell
.\scripts\vs-workspace.ps1 fetch-gamesrc essentials   # core mechanics, trading, player systems
.\scripts\vs-workspace.ps1 fetch-gamesrc survival     # blocks, items, food, world gen
```

Claude Code checks `gamesrc\` automatically when implementing anything that touches vanilla behaviour.

### Dependency mods (for Claude Code context)

```powershell
# From git URL
.\scripts\vs-workspace.ps1 add-dep https://github.com/someone/SomeMod.git

# From local folder or zip
.\scripts\vs-workspace.ps1 add-dep C:\downloads\SomeMod

# Manually: copy source to dependencies\SomeMod\, then add "SomeMod" to workspace.json dependencies array
```

For **build-time DLL references**, drop the DLL into `mods\MyMod\deps\somedep-1.21\` — it is automatically referenced for that VS version build.

---

## workspace.json

The neutral committed state. Fields that change per project (`targetMod`, `dependencies`, `examples`) are reset by `reset`. Everything else persists across sessions.

| Field | What it controls |
|---|---|
| `gameVersion` | Written into generated `modinfo.json` |
| `apiVersion` | Which `api\` subfolder Claude Code reads |
| `dotnetTarget` | .NET framework (`net7.0` for VS ≤1.21, `net8.0` for ≥1.22) |
| `gameDirectory` | Pre-filled into `localSettings.props` when scaffolding new mods |
| `targetMod` | Active mod for builds and Claude Code sessions |
| `dependencies` | Mod source folders Claude Code reads for context |
| `examples` | Example mod folders Claude Code studies for patterns |

---

## Full command reference

```
init                           Create workspace folder structure (run once)
status                         Show current configuration

fetch-api <version>            Clone vsapi, check out version commit
use-api <version>              Switch active API version
list-api                       List downloaded API versions

fetch-gamesrc <name> [ver]     Clone game source repo (essentials | survival)
list-gamesrc                   List fetched game source repos

add-dep <path-or-url> [name]   Add dependency mod source for Claude Code context
remove-dep <name>              Remove dependency from scope
list-deps                      List in-scope dependencies

add-example <path-or-url>      Add example mod for Claude Code context
remove-example <name>          Remove example from scope
list-examples                  List in-scope examples

new-mod <ModName>              Scaffold new mod (Directory.Build.props, csproj, source\, etc.)
import-mod <src> [Name]        Import existing mod (folder, zip, or git URL)
use-mod <ModName>              Set active mod target
list-mods                      List mods in mods\

build [debug|release]          Compile active mod
                                 debug:   active version only → bin\Debug\{vsver}\Mods\
                                 release: all versions → Releases\{modid}_{ver}_vs{vsver}.zip

publish-mod [branch] [remote]  Commit mod to branch and push  (default: mod/{modid}, origin)
export-mod [git-url]           Initialise mod as standalone repo; push if URL provided
reset [clean]                  Clear targetMod, dependencies, examples from workspace.json
                                 clean: also delete local api\, gamesrc\, mods\, deps\, examples\
```
