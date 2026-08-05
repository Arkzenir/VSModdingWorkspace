# Task: port the mod to another game version

Argument: the target version, e.g. `1.21.5`.

1. Read `workspace.json` for the current API version and target framework.
2. Make sure the target API source is cached:
   ```powershell
   .\scripts\vsmod.ps1 fetch-api <target>
   ```
3. Read all source and the existing `.csproj` files to establish the starting state.
4. Compare the old and new `api/vsapi/` trees for:
   - changed method signatures
   - renamed or moved types
   - changed JSON asset format requirements
   - target framework: `net7.0` for VS ≤1.20, `net8.0` for ≥1.21
5. Create `{ModName}_<target>.csproj` modelled on the existing one, with updated
   `<VSVersion>` and `<TargetFramework>`. Keep the old one — supporting several
   versions side by side is the point of the naming scheme.
6. Add a `GameDirectory_X_XX` entry to `Properties/localSettings.props.template`.
7. Fix the compile errors that surface, then build.

Summarise every breaking change found and how each was resolved. Flag anything you
worked around rather than genuinely fixed.
