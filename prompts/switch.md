# Task: switch to another mod

Argument: the workspace name. If none was given, run `list` and ask which one.

```powershell
.\scripts\vsmod.ps1 use <Name>
```

Switching is instant and re-downloads nothing — the API source, game source,
dependencies and examples are shared from `cache/` and relinked on the way in.

Afterwards:

1. Read the new `workspaces/<Name>/workspace.json`.
2. Read `mod/` to reload your understanding of this mod — do not carry assumptions
   over from the previous one. Different mod, different conventions, different API version.
3. Report what this mod is and its current state, then ask what to work on.

If `status` shows a missing link, the cache entry has not been fetched yet; tell the
user which `fetch-api` or `fetch-gamesrc` command fixes it.
