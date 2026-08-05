# Task: create a new mod

Argument: the mod name in PascalCase (e.g. `GlowingMushroom`).

## 1. Scaffold it

```powershell
.\scripts\vsmod.ps1 new <ModName>
```

This creates `workspaces/<ModName>/`, scaffolds the mod, initialises `mod/` as a git
repo with an initial commit, and makes the workspace active. If the workspace already
exists, do not re-run this — switch to it with `use <ModName>` instead.

## 2. Get your bearings

Read `workspaces/<ModName>/workspace.json`, then the generated files under
`workspaces/<ModName>/mod/` so you know the structure you are working in.

Confirm the API source is available at `workspaces/<ModName>/api/vsapi/`. If it is
missing, tell the user to run `.\scripts\vsmod.ps1 fetch-api <version>`.

## 3. Find out what to build

Ask what the mod should actually do — blocks, items, entities, behaviours, world gen,
mechanics. Ask about anything genuinely ambiguous, but do not interrogate: one round
of questions, then build.

## 4. Build it

Follow Task Mode A in AGENTS.md. Then compile:

```powershell
.\scripts\vsmod.ps1 build
```

Summarise what you built, what remains manual (textures to draw, DLLs to vendor), and
how to verify it in game.
