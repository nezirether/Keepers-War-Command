# KWC development workflow

## Branches and exchange

GitHub is the shared exchange point. `main` is the integrated branch. This laptop may edit, commit, and make ordinary pushes only on `work-laptop/development`. Verify the repository root, branch, HEAD, and working tree before editing. Share the agreed commit and relevant review context through GitHub. Give Codex Cloud an explicit branch or commit.

Home `dev/ui-2.0` and any other home branches may be active and newer. Leave them in place. Do not retire, rename, overwrite, or merge them as part of laptop work. Unpushed home work is unknown. Before any home pull, checkout, or merge, inventory local branches, their tips and upstreams, local-only commits, and staged, unstaged, and untracked changes. Preserve that work before proceeding and record the agreed base in the handoff.

Owner approval is required for merges, branch deletion, force pushes, destructive Git operations, and public releases. If a normal branch push is rejected, report the rejection and preserve local and remote work.

## Home AI Orchestrator

1. Claude implements the scoped change on the authorized development branch.
2. Codex reviews behavior, compatibility, and regression risks. Claude addresses findings and returns the updated diff for review.
3. The orchestrator runs essential checks, records the results, and prepares a private test ZIP from the validated commit.
4. Append the source and tested revisions, findings, test results, ZIP provenance, and next action to the [handoff log](HANDOFF.md).

Autonomous integration is enabled for in-scope implementation, review fixes, checks, and private packaging on the authorized home branch. Pause at any owner approval boundary or when proceeding could discard, overwrite, or expose work.

## Minimum checks and test ZIP

- For documentation-only changes, check links and confirm the diff is scoped. For addon changes, check changed Lua with Lua 5.1, verify TOC paths and load order, and run affected standalone suites from the root with Lua 5.1 or LuaJIT. Use `tests/raid_tools_initialization.lua` for the production load path and the guild sync release-gate and security suites for sync changes. Run applicable feature and security suites for a private test build. Record skipped checks and reasons, and list remaining Forever 1.60.1 client checks.
- Build the ZIP from the committed, tested revision. The archive root contains only `KeepersWarCommand/`. Verify `KeepersWarCommand/KeepersWarCommand.toc` and compare archive contents with the source commit. Record the full commit SHA, manifest version, ZIP path or name, and SHA-256. Follow the backup and rollback steps in [INSTALLATION.md](../INSTALLATION.md) for in-game testing.
