# Vintage Story Modding Workspace

You are an expert Vintage Story mod developer. This workspace is structured so you can **build new mods from scratch** or **diagnose and fix bugs in existing mods**, by referencing the active API version, dependency mods, and example mods defined in `workspace.json`.

---

## 🗂️ Workspace Layout

```
vs-modding-workspace\
├── CLAUDE.md                  ← You are here
├── workspace.json             ← Active configuration (READ THIS FIRST)
├── api\
│   └── {version}\vsapi\       ← Cloned vsapi source at that version tag (context only — no DLLs)
├── dependencies\
│   └── {ModName}\             ← Dependency mod source or decompiled code
├── examples\
│   └── {ModName}\             ← Reference/example mod source
├── mods\
│   └── {ModName}\             ← Your actual mod project(s) (BUILD TARGET)
└── scripts\
    └── vs-workspace.ps1       ← Workspace management CLI (PowerShell)
```

---

## 📋 Step 1 — Always Read workspace.json First

Before doing anything, read `workspace.json`. It tells you:
- `apiVersion` — which subfolder under `api\` contains the active vsapi source (for reading types/interfaces)
- `gameVersion` — the VS game version being targeted
- `dotnetTarget` — the .NET target framework (e.g. `net7.0`)
- `gameDirectory` — where the game is installed (game DLLs live here)
- `targetMod` — which mod under `mods\` you are building or fixing
- `dependencies` — which mods under `dependencies\` are in scope
- `examples` — which mods under `examples\` are in scope

> **Note:** `api\{version}\vsapi\` is **source code only** — no compiled DLLs. Build references
> come from the game install (`gameDirectory`). The api source is for Claude Code to read types and interfaces.

---

## 🔍 Step 2 — Understand the Active API

The API source lives at `api\{apiVersion}\vsapi\`. Key folders:

| Folder | What it contains |
|---|---|
| `Client\` | Client-side interfaces (ICoreClientAPI, GUIs, rendering) |
| `Common\` | Shared interfaces used by both client and server |
| `Server\` | Server-side interfaces (ICoreServerAPI) |
| `Math\` | Vec2/3/4, Matrix, BlockPos, etc. |
| `Datastructures\` | TreeAttribute, FastList, OrderedDictionary, etc. |
| `Config\` | Game config structures |

When implementing any feature:
1. Search the API source for relevant interfaces/classes before inventing anything.
2. Prefer existing API hooks (`RegisterBlockBehavior`, `Event.OnEntitySpawn`, etc.) over reflection or patches.
3. Check `Common\API\` for the main `ICoreAPI` interface surface.

---

## 📖 Step 2b — API Docs (Online Reference)

The hosted API docs at **https://apidocs.vintagestory.at/** are a searchable reference for every class, interface, and method. Use them alongside the local source — the docs show rendered summaries, parameter descriptions, and inheritance chains more clearly than raw source.

**URL patterns for direct lookup:**

| What you want | URL |
|---|---|
| All `Common` types | `https://apidocs.vintagestory.at/api/Vintagestory.API.Common.html` |
| All `Client` types | `https://apidocs.vintagestory.at/api/Vintagestory.API.Client.html` |
| All `Server` types | `https://apidocs.vintagestory.at/api/Vintagestory.API.Server.html` |
| A specific class | `https://apidocs.vintagestory.at/api/Vintagestory.API.Common.{ClassName}.html` |

**Examples:**
- `ICoreAPI` → `https://apidocs.vintagestory.at/api/Vintagestory.API.Common.ICoreAPI.html`
- `CollectibleObject` → `https://apidocs.vintagestory.at/api/Vintagestory.API.Common.CollectibleObject.html`
- `BlockBehavior` → `https://apidocs.vintagestory.at/api/Vintagestory.API.Common.BlockBehavior.html`

**When to fetch the docs:**
- You need exact method signatures, parameter names, or return types.
- You are unsure whether a method exists or has been renamed.
- You are debugging a bug that may stem from an API contract you haven't verified.
- The local source exists but the XML doc comments are sparse.

> **Note:** The hosted docs always reflect the **latest game version**. If you are targeting an older version, cross-check against the local `api\{apiVersion}\vsapi\` source for any differences.

---

## 🎮 Step 2c — Game Source Repos (Vanilla Implementation Reference)

The workspace can hold clones of the game's own mod source repos under `gamesrc\`. These are the most authoritative reference for how vanilla features are actually implemented — far more useful than guessing from the API surface alone.

| Folder | Repo | What it contains |
|---|---|---|
| `gamesrc\essentials\` | vsessentialsmod | Core systems: time, weather, player mechanics, trading, world interaction |
| `gamesrc\survival\` | vssurvivalmod | Survival content: blocks, items, food, animals, world gen, crafting |

**When to consult game source repos:**
- Implementing a feature that extends or interacts with vanilla behaviour (e.g. custom food, new trader stock, modified world gen).
- Trying to understand how a vanilla block/entity/system works before writing code that depends on it.
- Looking for the correct way to hook into a system when the API source alone is ambiguous.
- Porting a mod to a new VS version — check what changed in the vanilla implementation.

**How to use them:**
1. Check whether the repos are present: `gamesrc\essentials\` and/or `gamesrc\survival\`.
2. If present, search them for the relevant class or asset before writing new code.
3. Match naming conventions, JSON structure, and code patterns found in vanilla.
4. Never copy vanilla code verbatim into a mod — use it as a pattern reference only.

**If game source repos are not present:**
- You can still work from the API source and the online docs.
- Tell the user to run `fetch-gamesrc essentials` and/or `fetch-gamesrc survival` if deeper vanilla reference is needed.

---

## 📦 Step 3 — Learn from Dependencies & Examples

### Dependencies (`dependencies\`)
These are mods your target mod depends on at runtime. When building:
- Inspect their `modinfo.json` for modid and version.
- Study their public classes/interfaces so your mod can interact with them correctly.
- If the dep ships a DLL, it should be placed in `mods\{targetMod}\deps\{depname}-{vsver}\` for the build system to auto-reference.

### Examples (`examples\`)
These are reference mods showing patterns and conventions. When building:
- Study their project structure, asset layout, and code patterns.
- Use them as templates for common patterns (blocks, items, entities, GUIs, world gen, etc.).
- Prefer patterns you see in examples over inventing new ones.

---

## 🏗️ Step 4 — Mod Project Structure

Every mod scaffolded under `mods\{ModName}\` follows this layout:

```
mods\MyMod\
├── .gitignore
├── Directory.Build.props          ← Mod identity (name, id, version, description, side, authors)
├── Common.Build.targets           ← Shared MSBuild logic (imported by all .csproj files)
├── MyMod_1.19.csproj              ← Per-VS-version build (thin — just version + path resolution)
├── MyMod_1.20.csproj              ← Add one per supported VS version
├── Properties\
│   ├── localSettings.props.template  ← Committed — shows available path overrides
│   └── localSettings.props           ← Gitignored — machine-specific game install paths
├── source\
│   └── MyModModSystem.cs          ← ModSystem entry point (and other .cs files)
├── resources\
│   └── assets\
│       └── mymod\
│           ├── blocktypes\
│           ├── itemtypes\
│           ├── entities\
│           ├── recipes\
│           ├── lang\
│           │   └── en.json
│           └── patches\
├── deps\
│   └── somedep-1.19\              ← Vendored dep DLL for fallback (per VS version)
└── external\                      ← Ad-hoc DLLs auto-referenced by Common.Build.targets
```

> **modinfo.json is generated by MSBuild** from the properties in `Directory.Build.props`.
> Do not create a static `modinfo.json` — edit `Directory.Build.props` instead.
>
> **Assets are symlinked** from `resources\assets\` into the build output.
> Asset edits are immediately visible to the game without rebuilding.

---

### Directory.Build.props — Mod Identity

```xml
<Project>
  <PropertyGroup>
    <ModName>My Mod</ModName>
    <ModType>code</ModType>
    <ModVersion>1.0.0</ModVersion>
    <ModId>mymod</ModId>
    <Description>What the mod does.</Description>
    <Side>universal</Side>          <!-- universal | server | client -->
    <RequiredOnClient>true</RequiredOnClient>
    <RequiredOnServer>true</RequiredOnServer>
  </PropertyGroup>
  <ItemGroup>
    <ModInfoAuthors Include="Author" />
  </ItemGroup>
</Project>
```

### Per-version .csproj (thin)

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <VSVersion>1.19</VSVersion>
    <TargetFramework>net7.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <!-- Written into generated modinfo.json -->
    <Dependencies Include="game" Version=">=1.19.0" />
  </ItemGroup>
  <!-- Game path: localSettings.props > VINTAGE_STORY_1_19 env var > VINTAGE_STORY env var -->
  <PropertyGroup>
    <GameDirectory Condition="'$(GameDirectory_1_19)' != ''">$(GameDirectory_1_19)</GameDirectory>
    <GameDirectory Condition="'$(GameDirectory)' == ''">$(VINTAGE_STORY)</GameDirectory>
  </PropertyGroup>
  <Import Project="Common.Build.targets" />
</Project>
```

### ModSystem entry point pattern

```csharp
using Vintagestory.API.Common;

[assembly: ModInfo("MyMod", "mymod")]

namespace MyMod;

public class MyModModSystem : ModSystem
{
    public override void Start(ICoreAPI api)
    {
        base.Start(api);
        api.Logger.Debug("[MyMod] Mod loaded.");
    }

    public override void StartClientSide(ICoreClientAPI api) { }
    public override void StartServerSide(ICoreServerAPI api) { }
}
```

---

## ⚙️ Key API Patterns (Quick Reference)

### Registering content
```csharp
// In Start():
api.RegisterBlockClass("MyBlock", typeof(MyBlock));
api.RegisterItemClass("MyItem", typeof(MyItem));
api.RegisterEntity("MyEntity", typeof(MyEntity));
api.RegisterBlockBehaviorClass("MyBehavior", typeof(MyBehavior));
api.RegisterEntityBehaviorClass("myentitybehavior", typeof(MyEntityBehavior));
```

### Events
```csharp
sapi.Event.SaveGameLoaded += OnSaveGameLoaded;
sapi.Event.OnEntitySpawn += OnEntitySpawn;
sapi.Event.PlayerJoin += OnPlayerJoin;
capi.Event.BlockTexturesLoaded += OnTexturesLoaded;
capi.Event.RegisterRenderer(myRenderer, EnumRenderStage.Opaque);
```

### Network channels
```csharp
var channel = api.Network.RegisterChannel("mymod")
    .RegisterMessageType<MyPacket>();
// Server: channel.SendPacket(packet, player);
// Client: channel.SendPacket(packet);
```

### TreeAttributes (NBT equivalent)
```csharp
ITreeAttribute tree = entity.WatchedAttributes;
tree.SetInt("myKey", 42);
int val = tree.GetInt("myKey");
tree.MarkPathDirty("myKey");
```

---

## 📐 Coding Conventions

- Source files live in `source\`, assets in `resources\assets\{modid}\`.
- Do not create `modinfo.json` — it is generated from `Directory.Build.props`.
- Use `ICoreAPI` not concrete implementations where possible.
- Null-check `api.Side` when behaviour differs between client/server.
- Asset paths are always lowercase: `mymod:blocktypes/myblock`.
- Lang keys follow pattern: `block-mymod-myblock-desc`.
- Use `api.Logger.Debug/Warning/Error()` not `Console.WriteLine`.
- Use file-scoped namespace syntax: `namespace MyMod;` not the brace form.
- JSON patches use `{ "op": "add"|"replace"|"remove", "path": "...", "value": ... }`.

---

## 🚀 Task Mode A — Building a New Mod

When the request is to **create new functionality**:

1. Read `workspace.json` → confirm API version, game version, dotnet target, and target mod.
2. Scan the active API source for relevant hooks and types.
3. Review examples for matching patterns and conventions.
4. Review dependencies for any APIs your mod needs to call.
5. Generate files in `mods\{targetMod}\`:
   - If starting from scratch and no `Directory.Build.props` exists: create the full scaffold (Directory.Build.props, Common.Build.targets, .csproj, localSettings.props.template, source\, resources\, .gitignore).
   - If adding to an existing mod: add to `source\` and `resources\assets\` only. Update `Directory.Build.props` if mod identity changes.
6. Do **not** create a static `modinfo.json`.
7. Include all assets (JSON block/item defs, lang files, patches) in `resources\assets\{modid}\`.
8. Summarise what was built and any manual steps (e.g. adding a dep DLL to `deps\`).

---

## 🔧 Task Mode B — Fixing Bugs in an Existing Mod

When the request is to **fix a bug, crash, or broken behaviour**:

### Diagnosis workflow

1. Read `workspace.json` to confirm active mod and API version.
2. **Read all existing source files** under `mods\{targetMod}\source\` before touching anything.
3. Read `Directory.Build.props` and the `.csproj` files to understand declared dependencies and target framework.
4. If a crash log or error is provided, identify the exception type, stack trace, and offending line first.
5. Cross-reference the API source at `api\{apiVersion}\vsapi\` to check:
   - Whether a method signature has changed between versions.
   - Whether an interface has been renamed or moved.
   - Whether the mod subscribes to an event that no longer exists.
6. Check `resources\assets\` for malformed JSON, wrong domain prefixes, or missing lang keys.

### Common bug patterns

| Symptom | Likely cause |
|---|---|
| `NullReferenceException` in `Start()` | API object used before registration; wrong call order |
| Block/item not appearing | Wrong `modid:` prefix, filename typo, missing lang key |
| Crash on world load | Event handler throws; TreeAttribute type mismatch |
| Mod loads but does nothing | Event subscribed on wrong side; registration typo |
| Compile error — method not found | Method renamed/moved in this API version — search vsapi source |
| Recipe not working | Wrong domain, missing `"type"` field, bad output quantity |

### Fix workflow

1. Identify the **minimal change** needed — do not refactor unrelated code.
2. Apply the fix with a comment explaining what was wrong and why the fix works.
3. Scan the rest of the file for the same class of mistake after fixing.
4. Summarise: what the bug was, what caused it, what was changed, how to verify in-game.

---

## 🔁 Task Mode C — Iterating on an Existing Mod

When the request is to **extend, refactor, or improve** a mod that was imported with `import-mod` (rather than scaffolded fresh with `new-mod`):

### First — understand what you're working with

Before writing a single line, run through this checklist:

1. Read `workspace.json` — confirm `targetMod`, `apiVersion`, `gameVersion`.
2. Read **every file** in `mods\{targetMod}\` — `modinfo.json` (or `Directory.Build.props`), all `.csproj` files, all source files under `src\` or `source\`.
3. Identify the **build system style**:

| What you see | Style | What it means |
|---|---|---|
| `Directory.Build.props` + `Common.Build.targets` | Workspace-native | Full workspace integration — iterate freely |
| A `.csproj` with explicit references, no shared targets | Legacy / foreign | Works as-is; migrate if asked |
| No `.csproj` at all | Assets-only mod | No C# — only JSON/asset changes needed |

4. Note the **source layout** (`src\` vs `source\`) and **asset layout** (`assets\` vs `resources\assets\`) so you write new files in the right places.
5. Check the existing code for established patterns — naming conventions, how events are subscribed, how config is stored — and match them in any new code.

### Migrating a legacy mod to the workspace build system

If the mod has an old-style `.csproj` and the user asks to migrate (or it would make iteration much easier), do this:

1. Create `Directory.Build.props` with the mod's identity fields extracted from `modinfo.json` and the old `.csproj`.
2. Create `Common.Build.targets` using the workspace template — update `RootNamespace` to match the mod.
3. Rename or copy the old `.csproj` to `{ModName}_{vsver}.csproj` and strip out everything now handled by the shared targets (references, output paths, assembly name).
4. Create `Properties\localSettings.props.template` (and copy it to `localSettings.props`) with the game directory.
5. If assets are in `assets\`, move them to `resources\assets\` and update any hardcoded paths.
6. Delete the now-redundant static `modinfo.json` if present — it will be generated by MSBuild.
7. Tell the user to verify `localSettings.props` has their game path and run `build` to confirm.

> Only migrate if asked, or if the existing build system is broken/missing. Do not restructure a working foreign build system unprompted.

### Adding features to an existing mod

1. Read all existing source to understand what's already registered and how.
2. Identify the right place to add the new code — a new file, or extending an existing class.
3. For new blocks/items/entities: follow the exact naming and asset structure already used in the mod.
4. For new C# classes: match the existing namespace and file location (`src\` or `source\`).
5. Register new content in the existing `ModSystem.Start()` — do not create a second `ModSystem`.
6. Add lang entries to the existing `en.json` — do not create a second lang file.
7. Summarise what was added and confirm the build command to use.

---

## 🏗️ Build Commands

Tell the user to run from the workspace root in PowerShell:

```powershell
# Debug — compiles the csproj matching the active apiVersion
.\scripts\vs-workspace.ps1 build

# Release — compiles ALL csproj files, produces Releases\{modid}_{ver}_vs{vsver}.zip per version
.\scripts\vs-workspace.ps1 build release
```

**Debug output:** `mods\{ModName}\bin\Debug\{vsver}\Mods\{modid}\`
Point the game's ModPaths at `bin\Debug\{vsver}\Mods\` for live testing, or copy the folder to `%APPDATA%\VintagestoryData\Mods\`.

**Release output:** `mods\{ModName}\Releases\{modid}_{version}_vs{vsver}.zip`
Ready to upload to https://mods.vintagestory.at/
