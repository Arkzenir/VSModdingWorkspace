# Task: diagnose and fix a bug

Argument: a description of the problem, or a crash log.

Follow Task Mode B in AGENTS.md. Resist the urge to fix the first plausible cause you
spot — read first, then diagnose.

1. Read `workspace.json` to confirm the active mod and API version.
2. Read **all** source files before touching anything.
3. If a crash log was supplied, identify the exception type, the stack frame inside the
   mod, and the offending line before forming any theory.
4. Cross-reference `api/vsapi/` for methods renamed, interfaces moved, or signatures
   changed in this API version — a mod that used to compile often breaks this way.
5. Check `resources/assets/` for malformed JSON, wrong domain prefixes, missing lang keys.
6. Apply the **minimal** fix, with a comment explaining what was wrong and why this works.
7. Scan the rest of the codebase for the same class of mistake.

Then build to confirm, and summarise: what the bug was, its root cause, what changed,
and how to verify the fix in game.

If the evidence does not actually support a diagnosis, say so and state what additional
information would settle it. A confident guess is worse than an honest gap.
