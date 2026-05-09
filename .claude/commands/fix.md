Diagnose and fix the following issue in the current mod: **$ARGUMENTS**

Follow Task Mode B in CLAUDE.md:
1. Read `workspace.json` to confirm the active mod and API version.
2. Read **all** existing source files before touching anything.
3. If a crash log or error message is included above, identify the exception type and stack trace first.
4. Cross-reference the API source at `api\{apiVersion}\vsapi\` to check for renamed methods, moved interfaces, or changed signatures.
5. Apply the minimal fix needed with a comment explaining the cause.
6. Scan the rest of the codebase for the same class of mistake.

Summarise: what the bug was, what caused it, what was changed, and how to verify the fix in-game.
