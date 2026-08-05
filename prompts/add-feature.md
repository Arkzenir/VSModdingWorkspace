# Task: add a feature

Argument: a description of the feature.

## Before writing any code

1. Read `harness.json` and the active `workspace.json` to confirm the mod and API version.
2. Read every existing source file under `mod/source/` (or `mod/src/`) so you know what
   is already registered and how.
3. Search `api/vsapi/` for the hooks and types the feature needs. Check
   <https://apidocs.vintagestory.at/> when you need exact signatures.
4. Check `gamesrc/` for how vanilla implements something comparable, and `examples/`
   for an established pattern. Prefer an existing pattern over a new invention.

## Implementing

Follow Task Mode A in AGENTS.md.

- Register new content in the existing `ModSystem.Start()`; never add a second `ModSystem`.
- Add lang entries to the existing `en.json`; never create a second lang file.
- Put assets under `resources/assets/{modid}/` in the right subfolder.
- Do not create `modinfo.json` — edit `Directory.Build.props`.

## Finishing

Run `.\scripts\vsmod.ps1 build` and fix what it reports. Then summarise what was added,
which files changed, and how to verify it in game.
