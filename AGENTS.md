# Keepers War Command agent instructions

Start with [project state](docs/PROJECT_STATE.md), the latest entry in the [handoff log](docs/HANDOFF.md), and the [development workflow](docs/DEVELOPMENT_WORKFLOW.md). These are the shared instructions for Codex Desktop, Codex Cloud, Claude Code, Claude Desktop, and the home AI Orchestrator.

- Verify the repository root, branch, HEAD, and working tree before editing. GitHub is the shared exchange point and `main` is the integrated branch. This laptop may write only to `work-laptop/development`. Ordinary pushes to that branch are allowed.
- Treat home branches, including `dev/ui-2.0`, as potentially active and newer. Inventory and preserve unknown home-only work before any home pull, checkout, or merge. Leave home branches intact.
- Obtain owner approval for merges, branch deletion, force pushes, destructive Git operations, and public releases. Follow the workflow for safe autonomous orchestration.
- Target WoW Forever 1.60.1 (Interface `16001`) and Lua 5.1. Keep compatibility helpers addon-local. Never write to Blizzard's global `C_Spell`. Keep changes scoped and preserve SavedVariables, authorization, and sync behavior unless the task calls for a change.
- Claude implements, Codex reviews, and the home orchestrator runs essential checks and produces a private test ZIP from a committed revision. Append validation and artifact details to the handoff log.
