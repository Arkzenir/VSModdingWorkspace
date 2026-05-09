Port the current mod to Vintage Story version **$ARGUMENTS**.

1. Read `workspace.json` to confirm the current mod and API version.
2. Read all source files and the current `.csproj` to understand the starting state.
3. Check the API source at `api\$ARGUMENTS\vsapi\` (fetch it first if not present: `.\scripts\vs-workspace.ps1 fetch-api $ARGUMENTS`).
4. Identify breaking changes between the current version and $ARGUMENTS:
   - Changed method signatures (compare vsapi source)
   - Renamed or moved types
   - Updated JSON asset format requirements
   - .NET target framework: net7.0 for VS ≤1.20, net8.0 for VS ≥1.21
5. Create a new `{ModName}_$ARGUMENTS.csproj` modelled on the existing one with the updated `<VSVersion>` and `<TargetFramework>`.
6. Fix any compilation errors caused by API changes.
7. Update `localSettings.props.template` with a `GameDirectory` entry for the new version.
8. Run the build to confirm: `.\scripts\vs-workspace.ps1 build`

Summarise every breaking change found and how it was resolved.
