# Task: import an existing mod

Argument: a git URL, local folder, or `.zip` path. Optionally a workspace name after it.

## 1. Import it

```powershell
.\scripts\vsmod.ps1 import <source> [Name]
```

Existing git history is preserved, so a fork stays a fork. If there was no repo, one
is initialised. The workspace is created and made active, and the importer reports the
detected mod id, version, build system and layout.

## 2. Understand what arrived — before changing anything

Follow Task Mode C in AGENTS.md. Concretely:

- Read every file under `workspaces/<Name>/mod/`: `modinfo.json` or
  `Directory.Build.props`, every `.csproj`, every source file.
- Identify the build system: harness-native, foreign-but-working, or assets-only.
- Note the layout (`src/` vs `source/`, `assets/` vs `resources/assets/`) and commit
  to writing new files where the mod already puts them.
- Note the existing conventions — naming, how events are subscribed, how config is
  stored — and match them.

## 3. Check the API context matches

Compare the detected `apiVersion` in `workspace.json` against what the mod targets. If
the cached API source is missing, tell the user:

```powershell
.\scripts\vsmod.ps1 fetch-api <version>
```

## 4. Report, then wait

Summarise what the mod is, how it is built, what state it is in, and anything that
looks broken or outdated. Then ask what to change, add or fix.

Do not migrate the build system, reformat, or restructure anything unprompted. A
working foreign build system is not a defect.
