# VS Modding Workspace

A modular Claude Code workspace for building Vintage Story mods, designed to live in a git repo and support a clean branch-per-mod workflow.

## How it works

```
main branch           mod/mymod branch        standalone repo
─────────────         ──────────────────      ───────────────
CLAUDE.md             CLAUDE.md               mymod/
scripts\              scripts\                  src\
workspace.json        workspace.json            assets\
.gitignore            mods\MyMod\              modinfo.json
                        src\                   .git\
                        assets\
                        modinfo.json
```

The `main` branch holds only the tool. Mod source lives on a `mod/{modid}` branch (or its own repo). When you finish a session, `publish-mod` saves your work and `reset` clears the workspace back to neutral — ready for the next project.

---

## Prerequisites

| Tool | Install |
|---|---|
| **Git** | https://git-scm.com/download/win |
| **Claude Code** | See the Claude Code install card above |
| **.NET SDK** (7.0 or 8.0) | https://dotnet.microsoft.com/download |
| **PowerShell 5.1+** | Built into Windows 10/11 |
| **Vintage Story** | Installed — game DLLs are required to build |

> No extra tools needed. The script uses PowerShell's built-in JSON handling — no `jq` required.

---

## Reducing Terminal Use

The workspace is designed so the terminal is rarely needed after initial setup. Here's what replaces it:

### `setup.bat` — first-time setup, no terminal needed

Double-click `setup.bat` in Explorer. It handles script unblocking, execution policy, and folder structure in one step. After that, open the folder in VS Code and you're done with raw PowerShell permanently.

### VS Code tasks — `Ctrl+Shift+P` → Run Task

Every workspace command is available as a VS Code task (defined in `.vscode/tasks.json`). Tasks that need input (mod name, version number) show a native VS Code prompt — no terminal typing required.

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+B` | Build debug (default build task) |
| `Ctrl+Shift+P` → `Run Task` → `WS: ...` | Any other workspace command |

Key tasks:

| Task | What it does |
|---|---|
| `WS: Build Debug` | Compile and deploy to VS mods folder |
| `WS: Build Release` | Compile + produce distributable zip |
| `WS: New Mod` | Prompt for name, scaffold project |
| `WS: Import Mod` | Prompt for path/URL, import and inspect |
| `WS: Fetch API Version` | Prompt for version, clone vsapi |
| `WS: Fetch Game Source (Essentials/Survival)` | Clone vanilla game repos |
| `WS: Publish and Reset` | Push mod to branch + reset workspace in one step |
| `WS: Status` | Show workspace state |

### Claude Code slash commands — `/command`

Defined in `.claude/commands/`, these let you start any workflow without writing a prompt. Type them directly in Claude Code:

| Command | Does |
|---|---|
| `/new-mod MyMod` | Scaffolds the mod, then asks what to build |
| `/add-feature <description>` | Adds a feature following the full Task Mode A workflow |
| `/fix <description or log>` | Diagnoses and fixes a bug following Task Mode B |
| `/publish` | Runs publish-mod + reset and reports what was done |
| `/port 1.21.5` | Ports the mod to a new VS version |
| `/status` | Reports current session state and progress |

### VS Code extension recommendations

When you open the workspace, VS Code will offer to install the recommended extensions (`.vscode/extensions.json`). Accept them for C# IntelliSense, PowerShell syntax highlighting, and git graph visualisation.

---

## First-Time Setup

### Step 1 — First-time setup

**The easy way: double-click `setup.bat`** in Explorer. It handles script unblocking and execution policy automatically, then runs `init`.

If you prefer to do it manually, or if `setup.bat` fails:

```powershell
# Remove the "downloaded from internet" mark
Unblock-File .\scripts\vs-workspace.ps1

# Allow local scripts to run (once per machine)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

> **If you still see "not digitally signed"**: right-click `vs-workspace.ps1` → **Properties** → tick **Unblock** → OK, then retry.

---

### Step 2 — Initial workspace setup

Open a normal **PowerShell** window (no admin needed from here on):

```powershell
# Navigate to the workspace folder
cd C:\Users\YourName\projects\vs-modding-workspace

# Create directory structure
.\scripts\vs-workspace.ps1 init

# Add the vsapi source for your target game version (see "Adding the VS API" below)
.\scripts\vs-workspace.ps1 fetch-api 1.19.8

# Set your game install path in workspace.json (used when scaffolding new mods)
# Edit workspace.json: "gameDirectory": "C:\\Program Files\\Vintagestory"

# Verify everything is wired up
.\scripts\vs-workspace.ps1 status
```

---

## Adding the VS API

The `api\` folder holds the vsapi **source code**, which Claude Code reads to understand available types and interfaces. It is not used for compilation — build references come from your game install.

> **Note on versioning:** The vsapi repo has **no release tags**. Version-specific source is found by searching commit history — each game update is committed with a message referencing the version number (e.g. "1.19.8"). The `fetch-api` command handles this automatically.

**Option A — Automatic (requires Git and internet access)**
```powershell
.\scripts\vs-workspace.ps1 fetch-api 1.19.8
# Clones master, searches commit history for "1.19.8", checks out that commit
```

**Option B — Manual clone and checkout**

If you prefer to do it yourself:
```powershell
mkdir api\1.19.8
git clone https://github.com/anegostudios/vsapi.git api\1.19.8\vsapi

# Find the commit for your version
git -C api\1.19.8\vsapi log --oneline | Select-String "1.19.8"
# e.g. output: a3f91bc Update to version 1.19.8

# Check it out
git -C api\1.19.8\vsapi checkout a3f91bc

# Register it with the workspace
.\scripts\vs-workspace.ps1 use-api 1.19.8
```
Browse all commits at https://github.com/anegostudios/vsapi/commits/master if you need to find a specific version by eye.

**Option C — Manual copy (no Git needed)**

Download the source as a ZIP from https://github.com/anegostudios/vsapi (Code → Download ZIP) and extract it so the folder structure looks like this:
```
api\
└── 1.19.8\
    └── vsapi\
        ├── Client\
        ├── Common\
        ├── Server\
        └── ...
```
Note: the ZIP download always reflects the current master HEAD, not a specific version. For exact version matching, use Option A or B.

Then register it:
```powershell
.\scripts\vs-workspace.ps1 use-api 1.19.8
```

---

## Creating a New Mod

```powershell
# Scaffold the full project (Directory.Build.props, csproj, Common.Build.targets, source\, resources\, etc.)
.\scripts\vs-workspace.ps1 new-mod MyMod

# Open in VS Code
code .

# Launch Claude Code and tell it what to build
claude
```

The scaffold pre-fills `Properties\localSettings.props` with the `gameDirectory` from `workspace.json`.
Verify the path is correct before building.

---

## Building

```powershell
# Debug build — compiles the active apiVersion csproj
.\scripts\vs-workspace.ps1 build

# Release build — compiles ALL csproj files, produces Releases\*.zip per VS version
.\scripts\vs-workspace.ps1 build release
```

### Debug output
```
mods\MyMod\bin\Debug\1.19\Mods\mymod\
  MyMod_1.19.dll
  modinfo.json          <- generated from Directory.Build.props
  assets\               <- symlink to resources\assets\ (live, no rebuild needed)
```

To test: either copy the `mymod\` folder to `%APPDATA%\VintagestoryData\Mods\`, or add the
`bin\Debug\1.19\Mods\` folder to your game's ModPaths in `clientsettings.json`:

```json
"ModPaths": ["C:\\Users\\YourName\\projects\\vs-modding-workspace\\mods\\MyMod\\bin\\Debug\\1.19\\Mods"]
```

This means asset edits are live — change a JSON file in `resources\assets\` and relaunch the game,
no recompile needed. Only C# changes need a rebuild.

### Release output
```
mods\MyMod\Releases\
  mymod_1.0.0_vs1.19.zip
  mymod_1.0.0_vs1.20.zip    <- if you have a MyMod_1.20.csproj
```

These zips are ready to upload to https://mods.vintagestory.at/

---

## Importing and Iterating on an Existing Mod

Use `import-mod` to bring any mod into the workspace — from a local folder, a zip download, or a git repo — and then use Claude Code to extend, refactor, or fix it.

```powershell
# From a local folder
.\scripts\vs-workspace.ps1 import-mod C:\mods\SomeMod

# From a zip file (e.g. downloaded from mods.vintagestory.at)
.\scripts\vs-workspace.ps1 import-mod C:\Downloads\SomeMod.zip

# From a git repo
.\scripts\vs-workspace.ps1 import-mod https://github.com/someone/SomeMod.git

# With an explicit name (otherwise inferred from the source)
.\scripts\vs-workspace.ps1 import-mod C:\mods\SomeMod MyRenamedMod
```

After importing, the script will:
- Copy/clone/extract the mod into `mods\`
- Read `modinfo.json` to report the mod id and version
- Detect whether it uses the workspace build system or a legacy `.csproj`
- Set it as the active target mod in `workspace.json`
- Tell you exactly what to check before running Claude Code

Then open Claude Code and describe what you want:

```powershell
claude
```

> *"Add a config option to toggle the effect on/off"*
> *"Migrate this mod to the workspace build system"*
> *"Port this mod to VS 1.21 — it currently targets 1.19"*
> *"The loot table changes aren't working, here's the log..."*

Claude Code reads `CLAUDE.md → Task Mode C` which explains how to handle all of these cases, including how to detect the existing code structure, match its conventions, and migrate the build system if needed.

---

## Fixing Bugs in an Existing Mod

```powershell
# Copy the mod source into mods\
Copy-Item -Recurse C:\path\to\BrokenMod .\mods\BrokenMod

# Point workspace at it
.\scripts\vs-workspace.ps1 use-mod BrokenMod

# Open Claude Code and describe the problem
claude
```

> "The mod crashes on world load with NullReferenceException in BlockMyBlock.OnBlockPlaced. Log:"
> *[paste log]*

Claude Code reads all source, cross-references the active API version, finds the root cause, and
applies a minimal fix. See `CLAUDE.md → Task Mode B` for the full diagnostic process.

---

## Supporting Multiple VS Versions

Each VS version gets its own thin `.csproj` that shares `Common.Build.targets`:

```powershell
# Download API source for the second version
.\scripts\vs-workspace.ps1 fetch-api v1.20.0
```

Then in the mod folder, copy and update the csproj:
```powershell
Copy-Item mods\MyMod\MyMod_1.19.csproj mods\MyMod\MyMod_1.20.csproj
# Edit MyMod_1.20.csproj: set <VSVersion>1.20</VSVersion> and <TargetFramework>net8.0</TargetFramework>
```

Add the new game path to `Properties\localSettings.props`:
```xml
<GameDirectory_1_20>C:\Program Files\Vintagestory_1.20</GameDirectory_1_20>
```

Now `build release` compiles both and produces two zips.

---

## Adding Game Source Repos

The game's own mod source code is hosted on GitHub. Cloning it gives Claude Code a deep reference for how vanilla features are implemented — block behaviours, entity AI, world gen, crafting systems, trading, and more.

Two repos are supported out of the box:

```powershell
# VSEssentials - core player mechanics, weather, time, world interaction, trading
.\scripts\vs-workspace.ps1 fetch-gamesrc essentials

# VSSurvivalMod - survival content: blocks, items, food, animals, world gen, crafting
.\scripts\vs-workspace.ps1 fetch-gamesrc survival

# Optionally target a specific game version (searches commit history, same as fetch-api)
.\scripts\vs-workspace.ps1 fetch-gamesrc survival 1.21.5

# See what's fetched and what's available
.\scripts\vs-workspace.ps1 list-gamesrc
```

These clone into `gamesrc\essentials\` and `gamesrc\survival\`. Claude Code checks for them automatically at the start of every session (Step 2c in `CLAUDE.md`) and uses them as a reference when:
- Implementing features that extend vanilla behaviour
- Understanding how a vanilla system works before hooking into it
- Porting a mod across VS versions

Both repos follow the same "no release tags" pattern as vsapi — versions are found by searching commit history.

---

## Adding Dependency Mod Context

Dependencies are added so Claude Code can read their source when writing your mod. There are three ways to add them — pick whichever suits what you have.

**Option A — Git URL (clones automatically)**
```powershell
.\scripts\vs-workspace.ps1 add-dep https://github.com/copygirl/CarryCapacity.git
```

**Option B — Local path (copies the folder in)**
```powershell
.\scripts\vs-workspace.ps1 add-dep C:\downloads\SomeDep
# Optionally give it a different folder name inside dependencies\:
.\scripts\vs-workspace.ps1 add-dep C:\downloads\SomeDep-src CarryCapacity
```

**Option C — Manual copy (no script needed)**

Copy or extract the mod source directly into the `dependencies\` folder, then add its name to the `dependencies` array in `workspace.json`:
```
dependencies\
└── CarryCapacity\
    ├── src\
    └── modinfo.json
```
```json
"dependencies": ["CarryCapacity"]
```

All three options result in the same thing: a folder under `dependencies\` that Claude Code can read.

### Build-time DLL references

If the dependency ships a DLL your mod needs to link against at compile time, place it in the mod's `deps\` folder using the version-naming convention:
```
mods\MyMod\deps\somedep-1.19\somedep.dll
```
`Common.Build.targets` automatically references all DLLs in `deps\*-{vsver}\` for the matching VS version build. You can also drop DLLs into `external\` for version-agnostic one-offs.

---

## workspace.json Reference

```json
{
  "gameVersion": "1.19.8",
  "apiVersion": "1.19.8",
  "dotnetTarget": "net7.0",
  "targetMod": "MyMod",
  "gameDirectory": "C:\\Program Files\\Vintagestory",
  "dependencies": ["CarryCapacity"],
  "examples": ["VSModExamples"]
}
```

| Field | Purpose |
|---|---|
| `apiVersion` | Which `api\` subfolder Claude Code reads for API context |
| `gameVersion` | Game version targeted (written into generated modinfo.json) |
| `dotnetTarget` | .NET framework for new mods (net7.0 for VS 1.19–1.21, net8.0 for 1.22+) |
| `targetMod` | Active mod for `build`, `use-mod`, and Claude Code sessions |
| `gameDirectory` | Pre-filled into `localSettings.props` when scaffolding new mods |
| `dependencies` | Folders under `dependencies\` Claude Code reads for context |
| `examples` | Folders under `examples\` Claude Code studies for patterns |

---

## Project Structure (per mod)

```
mods\MyMod\
├── .gitignore
├── Directory.Build.props          ← Edit here: mod name, version, description, side, authors
├── Common.Build.targets           ← Shared MSBuild logic (output paths, refs, modinfo, zip)
├── MyMod_1.19.csproj              ← Per-VS-version build config (thin)
├── Properties\
│   ├── localSettings.props.template  ← Committed template showing available settings
│   └── localSettings.props           ← Gitignored — your machine's game install paths
├── source\                        ← C# source files
├── resources\
│   └── assets\mymod\              ← JSON assets (symlinked into build output)
├── deps\
│   └── somedep-1.19\              ← Vendored dep DLLs per VS version (auto-referenced)
└── external\                      ← Ad-hoc DLLs (auto-referenced)
```

**modinfo.json is generated — never edit it directly.** Change `Directory.Build.props` instead.

---

## Tips for Claude Code Sessions

- **New feature**: "Add a block called `glowing_mushroom` that emits light level 10 and can be placed on cave floors."
- **Bug fix**: "The mod crashes on world load with NullReferenceException in X. Here is the log:" — paste the full stack trace.
- **Multi-version**: "Add VS 1.20 support — duplicate the csproj and update the framework."
- **Dep integration**: "Use the CarryCapacity API to make this item carryable" — add the dep first with `add-dep`.
- **API lookup**: Claude Code will fetch https://apidocs.vintagestory.at/ directly when it needs to verify method signatures or check what's available in a class. You don't need to do anything — just ask.

---

## End of Session — Saving and Resetting

When you're done working on a mod, save it to a branch and reset the workspace.

### Option A — Branch in this repo (recommended for iterative work)

```powershell
# Push mod source to a branch called mod/{modid}
.\scripts\vs-workspace.ps1 publish-mod

# Custom branch name or remote
.\scripts\vs-workspace.ps1 publish-mod my-branch-name
.\scripts\vs-workspace.ps1 publish-mod mod/mymod upstream

# Reset workspace.json to neutral (targetMod, deps, examples cleared)
.\scripts\vs-workspace.ps1 reset
```

`publish-mod` does the following automatically:
1. Creates or resets branch `mod/{modid}` (or your custom name)
2. Force-adds `mods\{ModName}\` and the current `workspace.json`
3. Commits with message `Mod: {ModName} v{version}`
4. Pushes to `origin` (or your specified remote)
5. Returns you to the branch you were on before
6. Restores any stashed local changes

After `publish-mod`, run `reset` to clear `workspace.json`. The local `mods\` folder stays on disk (gitignored) but the branch has the committed version.

To resume work on a mod later:
```powershell
git checkout mod/mymod           # puts mods\MyMod\ back under git tracking
.\scripts\vs-workspace.ps1 use-mod MyMod
claude
```

---

### Option B — Standalone repo (for public release / separate project)

```powershell
# Initialise mods\MyMod as its own git repo and push to a remote
.\scripts\vs-workspace.ps1 export-mod https://github.com/YourName/MyMod.git

# Without a URL: just initialise the local git repo, push manually later
.\scripts\vs-workspace.ps1 export-mod
```

`export-mod` initialises a git repo inside `mods\{ModName}\`, commits all files, and pushes to the given URL. The mod folder becomes a self-contained project you can open, version, and release independently.

---

### Deep clean (full reset)

```powershell
# Reset workspace.json AND delete all local api\, gamesrc\, mods\, etc. folders
.\scripts\vs-workspace.ps1 reset clean
```

This asks for confirmation before deleting. After a clean reset, the workspace is identical to a fresh clone.

---

## Script Reference

```
build [debug|release]        Compile the active mod
  debug   -> active apiVersion csproj only, output to bin\Debug\{vsver}\Mods\
  release -> all csproj files, output to Releases\{modid}_{ver}_vs{vsver}.zip

fetch-api <version>          Download vsapi source, check out version commit
list-api                     Show all downloaded API versions
use-api <version>            Switch active API version in workspace.json

fetch-gamesrc <name> [ver]   Clone a game source repo (essentials, survival)
list-gamesrc                 Show fetched game source repos and available names

add-dep <path-or-url>        Add a dependency mod (for Claude Code context)
remove-dep <name>            Remove from scope
list-deps                    List in-scope dependencies

add-example <path-or-url>    Add an example mod (for Claude Code context)
remove-example <name>        Remove from scope
list-examples                List in-scope examples

new-mod <ModName>            Scaffold a new mod project from scratch
import-mod <src> [Name]      Import an existing mod (folder, zip, or git URL)
use-mod <ModName>            Set the active build target
list-mods                    List all mods in mods\

publish-mod [branch] [remote]  Commit mod to a branch and push (default: mod/{modid})
export-mod [git-url]           Initialise mod as standalone repo; push if URL given
reset [clean]                  Reset workspace.json to neutral; 'clean' also deletes
                                 local api\, gamesrc\, mods\, dependencies\, examples\

status                       Show full workspace state (API, game dir, deps, examples)
init                         Create directory structure (run once)
```
