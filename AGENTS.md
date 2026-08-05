# Vintage Story Modding Harness

You are an expert Vintage Story mod developer working inside a harness that keeps
one workspace per mod. Everything you need — the API source, vanilla game source,
dependency and example mods — is already on disk under the active workspace.

This file is the single source of truth for every agent. `CLAUDE.md`, `GEMINI.md`,
`.goosehints` and the rest are pointers back here; do not treat them as separate
instructions.

---

## Ground rules

1. **Read `harness.json` and the active `workspace.json` before anything else.**
2. **Only ever edit files under `workspaces/<active>/mod/`.** That folder is the
   mod. Everything beside it is read-only reference material.
3. **Never run `git push`, `git remote add`, or open a PR.** This harness only
   develops mods. The user copies the finished repo out and publishes it by hand.
   Committing inside `workspaces/<active>/mod/` is fine and encouraged; anything
   that touches a remote is not.
4. **Never edit anything under `cache/`.** It is shared by every workspace, so a
   change there silently affects unrelated mods.
5. **Do not create `modinfo.json`.** The build generates it from
   `Directory.Build.props`. Edit those properties instead.
6. **Never run `git clean -xfd`, `git clean -x`, or any recursive delete at the
   harness root.** Workspaces and the cache are deliberately gitignored, so `-x`
   would destroy every mod in the harness. If the user wants a workspace gone, tell
   them to run `.\scripts\vsmod.ps1 remove <Name>`.

---

## Two git repos, and which one you are in

This matters, because running a git command in the wrong directory is destructive.

| Repo | Root | Contains |
|---|---|---|
| The harness | harness root | The tooling: `AGENTS.md`, `scripts/`, `prompts/` |
| The mod | `workspaces/{active}/mod/` | The mod you are working on |

`harness.json`, `workspaces/`, `cache/` and `exports/` are gitignored at the harness
root, so the harness repo never sees mod work at all.

When you commit mod work, run git **inside the mod folder**, not the harness root:

```powershell
git -C workspaces/{active}/mod add -A
git -C workspaces/{active}/mod commit -m "Add glowing mushroom block"
```

A bare `git add -A` at the harness root does nothing useful and signals you have lost
track of where you are. Never stage harness files to record mod changes.

---

## Finding your bearings

```
harness-root/
├── harness.json                  Machine settings + which workspace is active
├── cache/                        Downloaded once, shared, read-only
│   ├── api/{version}/vsapi/
│   ├── gamesrc/{name}/
│   ├── dependencies/{name}/
│   └── examples/{name}/
├── scripts/vsmod.ps1             The CLI
├── prompts/                      Reusable task prompts
└── workspaces/
    └── {WorkspaceName}/
        ├── workspace.json        This mod's settings  <- READ FIRST
        ├── mod/                  THE MOD. A self-contained git repo. Edit here.
        ├── api/                  -> link into cache/api/{version}
        ├── gamesrc/{name}/       -> links into cache/gamesrc
        ├── dependencies/{name}/  -> links into cache/dependencies
        └── examples/{name}/      -> links into cache/examples
```

The active workspace name is `activeWorkspace` in `harness.json`. If you are unsure
which one is live, run `.\scripts\vsmod.ps1 status` — never guess.

`api/`, `gamesrc/`, `dependencies/` and `examples/` are directory junctions
(Windows) or symlinks (elsewhere) pointing into the shared cache. Read through them
normally; just never write through them.

### workspace.json

| Field | Meaning |
|---|---|
| `modName` | Display name, and the C# root namespace for scaffolded mods |
| `modId` | Lowercase alphanumeric id; also the asset domain (`modid:blocktypes/...`) |
| `modVersion` | Current version |
| `gameVersion` | Minimum game version written into `modinfo.json` |
| `apiVersion` | Which cached vsapi source `api/` points at |
| `dotnetTarget` | Target framework (`net7.0` for VS ≤1.20, `net8.0` for ≥1.21) |
| `gameDirectory` | Per-mod override; empty means inherit from `harness.json` |
| `dependencies`, `examples`, `gamesrc` | Which cached folders are linked in |

---

## Reference material, in order of authority

**1. Local API source — `api/vsapi/`**

The full C# API surface at the pinned version. Search it before inventing anything.

| Folder | Contents |
|---|---|
| `Client/` | `ICoreClientAPI`, GUIs, rendering |
| `Common/` | Shared interfaces; `Common/API/` has the main `ICoreAPI` surface |
| `Server/` | `ICoreServerAPI` |
| `Math/` | `Vec2/3/4`, `Matrix`, `BlockPos` |
| `Datastructures/` | `TreeAttribute`, `FastList`, `OrderedDictionary` |

Prefer existing hooks (`RegisterBlockBehavior`, `Event.OnEntitySpawn`) over
reflection or Harmony patches.

**2. Vanilla game source — `gamesrc/`**

`essentials` (time, weather, player mechanics, trading), `survival` (blocks, items,
food, animals, world gen, crafting), `creative`. The most authoritative reference
for how a vanilla feature actually works. Match its naming and JSON structure, but
never copy vanilla code verbatim into a mod.

If a repo you need is missing, tell the user to run
`.\scripts\vsmod.ps1 fetch-gamesrc survival`.

**3. Online docs — <https://apidocs.vintagestory.at/>**

Rendered summaries, parameter descriptions and inheritance chains. Useful when the
local XML doc comments are sparse.

- `https://apidocs.vintagestory.at/api/Vintagestory.API.Common.{ClassName}.html`
- Same pattern for `.Client.` and `.Server.`

These docs always track the **latest** game version. Cross-check against the local
`api/vsapi/` source when targeting anything older.

**4. `dependencies/` and `examples/`** — read-only source context. Inspect a
dependency's `modinfo.json` for its modid and version, and its public classes so you
call them correctly. Prefer patterns you can see in examples over inventing new ones.

---

## Mod layout

```
mod/
├── .git/                          It is already a repo. Commit freely; never push.
├── .gitignore
├── README.md
├── Directory.Build.props          Mod identity -> generates modinfo.json
├── Common.Build.targets           Shared build logic
├── MyMod_1.21.5.csproj            One per supported game version
├── Properties/
│   ├── localSettings.props        Machine game paths (gitignored)
│   └── localSettings.props.template
├── source/                        C# source
├── resources/
│   ├── modicon.png                Optional 32x32, copied to output automatically
│   └── assets/{modid}/
│       ├── blocktypes/ itemtypes/ entities/ recipes/ worldgen/ config/ patches/
│       ├── lang/en.json
│       ├── textures/{block,item,entity,gui}/     PNG
│       ├── shapes/{block,item,entity}/           VS JSON cube-model format
│       ├── sounds/ music/                        OGG
├── deps/{name}-{vsver}/           Vendored dependency DLLs, per version
└── external/                      Ad-hoc DLLs, auto-referenced
```

Assets are symlinked into the build output, so JSON, texture and sound edits are
live in-game without rebuilding. Only C# changes need a recompile.

### Asset references

| Type | Path | Referenced as |
|---|---|---|
| Textures | `textures/block/…` | `"texture": { "base": "block/stone/granite" }` |
| Shapes | `shapes/item/…` | `"shape": { "base": "item/simplewand" }` |
| Sounds | `sounds/…` | `"sounds": { "place": "block/stone" }` |
| Vanilla anything | — | prefix `game:` — `"game:block/metal/copper"` |

Shapes use Vintage Story's own JSON cube-model format, not FBX or OBJ. Simple flat
items render from their texture alone and need no shape file.

---

## Conventions

- Source in `source/`, assets in `resources/assets/{modid}/`.
- File-scoped namespaces: `namespace MyMod;` not the brace form.
- `ICoreAPI` over concrete implementations where practical.
- Check `api.Side` when behaviour differs between client and server.
- Asset paths are always lowercase: `mymod:blocktypes/myblock`.
- Lang keys follow `block-mymod-myblock-desc`.
- `api.Logger.Debug/Warning/Error()`, never `Console.WriteLine`.
- JSON patches: `{ "op": "add"|"replace"|"remove", "path": "...", "value": ... }`.

### ModSystem entry point

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

### Frequently needed API

```csharp
// Registration, in Start()
api.RegisterBlockClass("MyBlock", typeof(MyBlock));
api.RegisterItemClass("MyItem", typeof(MyItem));
api.RegisterEntity("MyEntity", typeof(MyEntity));
api.RegisterBlockBehaviorClass("MyBehavior", typeof(MyBehavior));

// Events
sapi.Event.SaveGameLoaded += OnSaveGameLoaded;
sapi.Event.PlayerJoin     += OnPlayerJoin;
capi.Event.BlockTexturesLoaded += OnTexturesLoaded;

// Network
var channel = api.Network.RegisterChannel("mymod").RegisterMessageType<MyPacket>();

// TreeAttributes (the NBT equivalent)
entity.WatchedAttributes.SetInt("myKey", 42);
entity.WatchedAttributes.MarkPathDirty("myKey");
```

---

## Task modes

### A — Building new functionality

1. Read `workspace.json`; confirm mod, API version, target framework.
2. Search `api/vsapi/` for the relevant hooks and types.
3. Check `examples/` for a matching pattern and `gamesrc/` for the vanilla approach.
4. Write into `mod/source/` and `mod/resources/assets/{modid}/`.
5. If the mod has no scaffold yet, create the full structure; otherwise only add.
6. Build to confirm it compiles. Summarise what you built and any manual step left
   (a dependency DLL to vendor, a texture to draw).

### B — Fixing a bug

1. Read **every** source file in `mod/` before changing anything.
2. If given a crash log, identify exception type, stack frame and offending line first.
3. Cross-reference `api/vsapi/` for renamed methods, moved interfaces, changed signatures.
4. Check `resources/assets/` for malformed JSON, wrong domain prefixes, missing lang keys.
5. Make the **minimal** fix, with a comment explaining the cause.
6. Scan the rest of the file for the same class of mistake.

| Symptom | Usual cause |
|---|---|
| `NullReferenceException` in `Start()` | API object used before registration, or wrong call order |
| Block/item missing in game | Wrong `modid:` prefix, filename typo, missing lang key |
| Crash on world load | Handler throws, or `TreeAttribute` type mismatch |
| Loads but does nothing | Subscribed on the wrong side, or a registration typo |
| Compile error, method not found | Renamed in this API version — search `api/vsapi/` |
| Recipe ignored | Wrong domain, missing `"type"`, bad output quantity |

### C — Iterating on an imported mod

Imported mods were not written by this harness. Before touching one:

1. Read every file: `modinfo.json` or `Directory.Build.props`, all `.csproj`, all source.
2. Identify the build system:

| What you see | Meaning |
|---|---|
| `Directory.Build.props` + `Common.Build.targets` | Harness-native — iterate freely |
| A `.csproj` with explicit references | Foreign but working — leave it alone unless asked |
| No `.csproj` | Assets-only mod — JSON and asset changes only |

3. Note the existing layout (`src/` vs `source/`, `assets/` vs `resources/assets/`)
   and put new files where the mod already puts them, not where you would prefer.
4. Match the established naming, event-subscription and config patterns.
5. Register new content in the existing `ModSystem.Start()` — never add a second
   `ModSystem`. Add lang entries to the existing `en.json` — never a second file.

**Migrating a foreign mod to the harness build system** (only when asked, or when
the existing build is broken):

1. Create `Directory.Build.props` from the identity fields in `modinfo.json` and the old `.csproj`.
2. Add `Common.Build.targets`, setting `RootNamespace` to match the mod.
3. Rename the `.csproj` to `{ModName}_{vsver}.csproj` and strip everything the
   shared targets now handle: references, output paths, assembly name.
4. Add `Properties/localSettings.props.template` and a local copy with the game path.
5. Move `assets/` to `resources/assets/` and fix any hardcoded paths.
6. Delete the static `modinfo.json` — it becomes generated.
7. Build to confirm, and tell the user to check `localSettings.props`.

### D — Porting to another game version

1. Make sure the target API is cached: `.\scripts\vsmod.ps1 fetch-api <version>`.
2. Diff the old and new `api/vsapi/` for changed signatures and moved types.
3. Copy the `.csproj` to `{ModName}_{newver}.csproj`; update `<VSVersion>` and
   `<TargetFramework>` (`net7.0` for VS ≤1.20, `net8.0` for ≥1.21).
4. Add a `GameDirectory_X_XX` entry to `localSettings.props.template`.
5. Fix the resulting compile errors and summarise every breaking change found.

---

## Commands

Run from the harness root. On Windows PowerShell, prefix with `.\`; with PowerShell 7
on other platforms use `pwsh scripts/vsmod.ps1 …`.

```
vsmod.ps1 status                     Active workspace, versions, link health
vsmod.ps1 list                       Every workspace
vsmod.ps1 use <Name>                 Switch workspace (instant, downloads nothing)
vsmod.ps1 build [debug|release]      Compile the active mod
vsmod.ps1 fetch-api <version>        Cache vsapi source and link it in
vsmod.ps1 fetch-gamesrc <name>       Cache vanilla source (essentials|survival|creative)
vsmod.ps1 add-dep <path-or-url>      Add dependency source context
vsmod.ps1 add-example <path-or-url>  Add example mod context
vsmod.ps1 add-dep-dll <name> <vsver> Vendor a dependency DLL into mod/deps/
vsmod.ps1 export [path]              Copy the mod repo out for the user to push
```

Suggest `export` when work is done, but never run a push yourself.

### Adding a dependency you must compile against

Reading a dependency's source is not enough to call it — the compiler needs its DLL.
Resolution happens in three tiers, in order:

1. `$(GameDirectory)/Mods/*.dll` — automatic when the dep is installed with the game.
2. `mod/deps/{name}-{vsver}/*.dll` — vendored, travels with the repo.
3. `mod/external/*.dll` — ad-hoc.

Tier 2 is populated with `add-dep-dll`. For a dep needing a per-machine overridable
path, add to the `.csproj`:

```xml
<PropertyGroup>
  <CarryCapacityDir Condition="'$(CarryCapacityDir_1_21)' != ''">$(CarryCapacityDir_1_21)</CarryCapacityDir>
  <CarryCapacityDir Condition="'$(CarryCapacityDir)' == ''">$(GameDirectory)/Mods/CarryCapacity</CarryCapacityDir>
  <CarryCapacityDir Condition="'$(CarryCapacityDir)' == ''">$(MSBuildProjectDirectory)/deps/carrycapacity-1.21</CarryCapacityDir>
</PropertyGroup>
```

a `<Reference>` in `Common.Build.targets` after the game DLLs, a commented entry in
`localSettings.props.template`, and a `<Dependencies Include="carrycapacity" …/>`
item so it lands in the generated `modinfo.json`.

---

## Build output

- **Debug** → `mod/bin/Debug/{vsver}/Mods/{modid}/`. Point the game's ModPaths at the
  `Mods/` folder above it for live asset reloading.
- **Release** → `mod/Releases/{modid}_{version}_vs{vsver}.zip`, ready for the mod portal.

If a build fails on missing game DLLs, the cause is almost always
`Properties/localSettings.props` pointing at the wrong install — check that before
suspecting the code.
