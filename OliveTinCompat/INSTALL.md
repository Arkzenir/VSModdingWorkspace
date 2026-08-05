# OliveTin control panel for the VS Modding Harness

A web UI over `vsmod.ps1`. Buttons for the things you do constantly (build,
switch mod, fetch sources), a live-updating card per workspace, and log output
in the browser instead of a terminal you have to keep finding.

Everything here is additive. `vsmod.ps1` is not modified, and the CLI keeps
working exactly as it does now.

---

## What's in this folder

| File | Goes where | What it does |
|---|---|---|
| `config.yaml` | `C:\OliveTin\config.yaml` | The whole UI: actions, entities, dashboards |
| `vsmod-web.ps1` | `<harness>\scripts\` | Adapter — runs `vsmod.ps1` without a terminal |
| `vsmod-entities.ps1` | `<harness>\scripts\` | Read-only; turns harness state into JSON the UI watches |
| `vsmod-pick.ps1` | `<harness>\scripts\` | Opens a native Windows file/folder dialog and publishes the choice |

---

## 1. Install

### Prerequisites

PowerShell 7 (`pwsh`). The harness itself runs on Windows PowerShell 5.1, but
OliveTin's own docs call `pwsh` for PowerShell actions and PS7 handles UTF-8
output far better in a non-console context.

```powershell
winget install Microsoft.PowerShell
```

### Get OliveTin

Download `OliveTin-windows-amd64.zip` from the releases page and extract so you
have:

```
C:\OliveTin\
  OliveTin.exe
  webui\
  config.yaml      <- from this folder
  entities\        <- create it, empty
```

```powershell
New-Item -ItemType Directory C:\OliveTin\entities -Force
```

### Drop in the scripts

```powershell
Copy-Item vsmod-web.ps1, vsmod-entities.ps1, vsmod-pick.ps1 C:\dev\VSModdingWorkspace\scripts\
Get-ChildItem C:\dev\VSModdingWorkspace\scripts\*.ps1 | Unblock-File
```

That `Unblock-File` matters — Windows marks anything that arrived from a
browser, and a blocked script fails with a confusing error under `-File`.

### Edit the three paths

Open `config.yaml` and find-and-replace:

| Placeholder | Replace with |
|---|---|
| `C:/dev/VSModdingWorkspace` | your harness root (the folder holding `harness.json`) |
| `C:/OliveTin` | wherever you extracted OliveTin |
| `C:/Program Files/PowerShell/7/pwsh.exe` | output of `(Get-Command pwsh).Source` |
| `C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe` | rarely needs changing |

Forward slashes on purpose — Windows accepts them and they avoid YAML escaping.

### Run it

```powershell
cd C:\OliveTin
.\OliveTin.exe
```

Open <http://127.0.0.1:1337>. You should see five dashboards across the top:
**Workbench**, **Add**, **Workspaces**, **Linked**, **Cache**.

**Run it in a terminal under your own account, not as a Windows service.** Two
independent reasons now:

1. A service runs as LocalSystem, which has no user `PATH` — no `git`, no
   `dotnet`, no per-user toolchain — so your first build fails with `command not
   found`.
2. The file dialogs draw on your desktop. A service lives in session 0, where
   nothing you can see exists, so a dialog would open invisibly and the action
   would hang until it timed out.

The second one has no workaround. If you want OliveTin always-on, install the
service *and* set it to log on as your own user account — but the dialogs will
still not appear, so keep the git-URL and drop-folder routes for those cases.

---

## 2. Verify

In order — each step confirms one layer:

1. **Entities.** Within two minutes, `C:\OliveTin\entities\` should contain six
   `.json` files. If not, run the generator by hand and read the error:
   ```powershell
   pwsh -NoProfile -File C:\dev\VSModdingWorkspace\scripts\vsmod-entities.ps1 `
        -HarnessRoot C:\dev\VSModdingWorkspace -OutDir C:\OliveTin\entities
   ```
2. **The adapter.** From a terminal:
   ```powershell
   pwsh -NoProfile -File C:\dev\VSModdingWorkspace\scripts\vsmod-web.ps1 - status
   ```
   Should print the same thing `vsmod.ps1 status` does.
3. **The UI.** Press **Show status** on the Workbench, then reload the page —
   the Status panel should fill with the same output.
4. **A dialog.** Add tab → **Browse for a folder**. A native Windows folder
   dialog should appear on your desktop. Pick anything; a "Selected: …" card
   appears on the same dashboard within a second or two.
5. **A real build.** Press **Build debug**. Watch the log stream, then reload
   and check the Last debug build panel. This is the step that tells you whether
   the whole idea is worth keeping.

---

## 3. How it's put together

### Not every command becomes a button

Your 20-odd verbs collapse into three groups:

- **`list`, `list-api`, `list-gamesrc`, `list-deps`, `list-examples`, `cache
  list`** — these aren't buttons. `vsmod-entities.ps1` reads the same state and
  writes it as entity files, and OliveTin renders those as cards. The list *is*
  the UI.
- **`use`, `use-api`, `remove`, `remove-dep`, `remove-example`, `cache
  remove`** — these take an item name, so they become one button *per item*,
  generated from the entity. You never type a workspace name; you press the
  button on that workspace's card.
- **Everything else** — real buttons with typed argument forms.

### The call convention

Every action shells out the same way:

```
pwsh -NoProfile -File vsmod-web.ps1 <answer|-> <verb> [args...]
```

`exec:` is used throughout rather than `shell:`. On Windows `shell:` wraps
things in `cmd /C`, not PowerShell, and OliveTin refuses to combine `shell:`
with the argument types needed for file paths. `exec:` passes an argv array
straight to the OS — no quoting layer, no escaping.

### The confirmation shim

`vsmod.ps1` calls `Read-Host` on `remove` and `cache remove`. In a web UI
nothing can answer that, so the action would hang until it timed out.

`vsmod-web.ps1` handles it by dot-sourcing `vsmod.ps1` into a scope where a
local `Read-Host` function shadows the cmdlet and returns the answer passed as
the first argument. The real gate becomes the browser confirmation checkbox,
which is what you want anyway — it shows a warning first, and the button says
what it's deleting.

If you'd rather not rely on that, add a `-Force` switch to `vsmod.ps1` at the
two `Read-Host` call sites (lines 583 and 1732) and drop the shim.

### Picking local paths

A browser cannot hand a server a local path. `<input type=file>` gives the page
the file's *contents* and deliberately withholds the path, and OliveTin has no
upload mechanism — so there is no way for the web UI to tell `vsmod.ps1` where
something is on disk. Typing a path was never a design choice; it was the only
thing a web UI could do.

The way around it is to open the dialog on the *server* side. Since the server
is your own dev machine, `vsmod-pick.ps1` calls the real
`FolderBrowserDialog` / `OpenFileDialog`, which appears on your desktop.

It runs under `powershell.exe` (5.1), not `pwsh`. WinForms dialogs require a
single-threaded apartment; PS 5.1 is STA by default, PS 7 is MTA and has no
`-STA` switch. The script uses no PS7-only syntax, so this costs nothing.

The flow is two steps, and that turns out to be better rather than worse:

1. **Add** → *Browse for a folder* / *a .zip* / *a .dll*. Dialog opens, you pick.
2. The selection is written to `picked.json`, which OliveTin watches, so a card
   appears within about a second showing what you chose — and then you decide
   what to do with it: import as a workspace, add as a dependency, add as an
   example, vendor a DLL, or export to it.

`enabledExpression` greys out the options that don't apply, so a `.dll` only
offers *Vendor selection into deps*, and only a folder offers *Export mod to
selection*. Cancelling a dialog leaves the previous selection alone.

The `.dll` browser opens in the game's Mods folder by default — change the
`-StartIn` value on that action if your install is elsewhere. This is the
`add-dep-dll` "searches automatically" behaviour made visible: instead of
trusting an invisible search, you see and confirm the exact DLL.

**If you ever run OliveTin somewhere without a desktop**, the alternative is a
drop folder: point an entity at `C:\ModDrop`, scan it on a cron, and generate one
import button per item found. Same no-typing property, no dialog needed. See
<https://docs.olivetin.app/solutions/directory-actions/index.html>. You can also
have `execOnFileCreatedInDir` import a zip automatically the moment it lands.

### Output on the dashboard

`type: stdout-most-recent-execution` puts an action's last output straight onto
a dashboard, so the Logs tab is no longer part of the loop. The Workbench has
three of these: **Status**, **Last debug build**, **Last release build**.

Two things to know about how it behaves:

- Its `title:` is the action's **`id:`**, not the action's display title. That's
  why `Show status`, `Build debug` and `Build release` carry explicit ids
  (`vsmod_status`, `build_debug`, `build_release`).
- **The panel refreshes on page load, not live.** Pressing a button does not
  update the panel below it. So the status action also runs `execOnStartup`, on
  a two-minute cron, and as a `triggers:` target of everything that changes
  state — the stored output stays fresh, and a page refresh always shows current
  reality.

For live-updating information, use an entity display instead. Entity files *are*
watched, so the active-mod panel at the top of the Workbench — mod id, API
version, linked deps and examples, last release zip and its timestamp — updates
without a reload. That's why `vsmod-entities.ps1` emits `active.json` as a
zero-or-one-row entity: the panel simply doesn't render when nothing is active.

In practice you get both: the live header tells you *what state you're in*, and
the output panels tell you *what happened last*. During a build you'd still
watch the execution dialog, which streams.

### State refresh

A hidden action runs `vsmod-entities.ps1` on startup, every two minutes, and as
a `triggers:` target of every action that mutates state. So activating a
workspace immediately re-renders the cards with the new active flag, rather than
you waiting for the cron.

Entity files are written atomically (temp file, then move) because OliveTin
watches them and would otherwise occasionally read a half-written file.

---

## 4. Using it

**Daily loop.** Workspaces tab → press **Activate** on the mod you want →
Workbench tab → **Build debug**. Two taps to switch context and build. The
Workbench header updates to the newly active mod on its own; the output panels
below it fill in on the next page refresh.

**New mod.** Add → **New mod** → type a PascalCase name. It scaffolds,
git-inits, and activates in one go, and the new card appears within seconds.

**Adding agent context from disk.** Add tab → **Browse for a folder** → pick →
then **Add selection as dependency** or **Add selection as example** on the card
that appears. Leave the name blank to derive it from the folder.

**Adding agent context from GitHub.** Add tab → **Add dependency from git URL**.
No dialog involved; the field is typed as a URL so it validates before running.

**Vendoring a dependency DLL.** Add tab → **Browse for a .dll** (opens in the
game Mods folder) → **Vendor selection into deps**, then fill in the mod id and
game version.

The **Linked** tab shows what the active workspace currently has linked, each
with an unlink button.

**Fetching sources.** Add → **Fetch API version** (`1.21.5`) or **Fetch
game source** (dropdown of survival / essentials / creative). These are long
git clones — the timeout is set to 30 minutes.

**Pruning.** Cache tab lists every cached item as `<kind>/<name>` with a purge
button. After purging anything, press **Sync cache links** in each workspace
that referenced it.

**From your phone or a tablet.** The UI is touch-friendly, but the config binds
to `127.0.0.1` deliberately. Only change that to `0.0.0.0` after setting up
authentication — these buttons run builds and delete directories on your dev
machine, and an unauthenticated port that does that is a genuinely bad idea.

---

## 5. Known rough edges

**Release zips have no download link.** `build release` produces
`mod\Releases\<modid>_<ver>_vs<vsver>.zip` and the web UI shows you stdout, not
the filesystem. The Workbench header at least names the most recent zip and when
it was built, so you know what you're looking for; you still open Explorer to
get it. Fixable by serving that folder over HTTP separately.

**Output panels don't live-update.** Page refresh required, as explained above.
The live header covers most of what you'd want mid-session.

**File dialogs need an interactive session.** Covered above, but worth
repeating because the failure mode is a hung action rather than an error: no
desktop, no dialog. `vsmod-pick.ps1` checks `[Environment]::UserInteractive` and
exits with an explanation instead of hanging.

**The dialog steals focus,** and only one can be open at a time. If a browse
action seems stuck, check whether a dialog is waiting behind your browser
window.

**No pipelines.** `fetch-api` → `use-api` → `new` → `build` is a chain and
OliveTin only does fire-after-completion, not branching flows. Fine at this
scale; if your workflows grow real conditionals, that's when Windmill starts
earning its extra complexity.

**Concurrency isn't wired up yet.** `vsmod.ps1` rewrites `harness.json` and
`workspace.json`, so two overlapping runs can lose writes. There's a
commented-out `actionGroups` block at the bottom of `config.yaml` — the group
syntax is confirmed, but the property that attaches an *action* to a group
varies between releases, so check
<https://docs.olivetin.app/action_customization/concurrency.html> against your
version and add it. Worth doing before you leave this running unattended.

**Killed builds can orphan children.** If a build times out, `pwsh` dies but
`dotnet`/`MSBuild` children may not. Windows has no process groups in the Unix
sense. Usually harmless here; occasionally you'll find a stale `dotnet` holding
a file lock.

---

## 6. If something doesn't load

**Config errors on startup** — OliveTin logs them to the terminal, and as a
service to `%ProgramData%\OliveTin\logs\`. Read that first; a YAML error means
the whole config is skipped, not just the broken action.

**An argument is rejected.** The type table is at
<https://docs.olivetin.app/args/types.html>. Two traps this config already
works around: `ascii` allows *no* punctuation, so `1.21.5` needs
`ascii_identifier`; and optional text fields use a `regex:` type whose `*`
quantifier permits an empty submission, since a strict type would reject blank.

**Entity cards don't appear** — check the JSON files exist and have content.
This config emits newline-delimited JSON objects, matching OliveTin's shipped
examples. If your version wants a JSON array instead, change `Write-EntityFile`
in `vsmod-entities.ps1` to emit one; see
<https://docs.olivetin.app/entities/json.html>.

**`enabledExpression` warnings in the log** — the greyed-out Activate button on
the already-active workspace uses one. If your version parses it differently,
delete those two lines; you lose only the greying-out.

---

## 7. Worth a look once this is running

Two OliveTin integrations that fit what you're building:

- **Stream-Deck** — <https://docs.olivetin.app/integrations/stream-deck.html>.
  A physical **Build debug** key is a meaningfully better experience than a
  browser tab.
- **MCP servers** — <https://docs.olivetin.app/integrations/mcp.html>. Exposes
  these same actions as agent tools, so your harness's agents call the identical
  code path your buttons do. Given the whole point of this workspace is feeding
  context to coding agents, that's the natural next step.
