Add the following feature to the current mod: **$ARGUMENTS**

Before writing any code:
1. Read `workspace.json` to confirm the active mod and API version.
2. Read all existing source files in `mods\{targetMod}\source\` to understand what is already implemented.
3. Check the API source at `api\{apiVersion}\vsapi\` and the API docs at https://apidocs.vintagestory.at/ for relevant hooks and types.
4. Check `gamesrc\` if present for vanilla patterns that match this feature.

Then implement the feature following Task Mode A in CLAUDE.md. When done, tell me what was built and run the debug build to confirm it compiles.
