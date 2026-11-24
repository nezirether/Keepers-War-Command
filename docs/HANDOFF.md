# KWC handoff

## Current handoff

- **Task and scope** — Establish shared agent documentation for Claude Desktop, Codex Desktop, Codex Cloud, and the home AI Orchestrator. This task adds documentation only.
- **Source baseline** — Secondary USB checkout, `work-laptop/development` at `e5afb94` (KWC `1.7.0`). The working tree was clean before the documentation additions. Home PC state is unverified and may include newer unpushed code.
- **Validation** — Repository docs, manifest, compatibility code, architecture, and test entry points inspected. Lua 5.1 and LuaJIT were unavailable on the USB workstation's shell PATH. Lua and in-game checks were skipped for this documentation task.
- **Artifact and next action** — Documentation is ready for owner review. This task generated no addon ZIP. Verify the home branch, HEAD, and local changes before choosing the base for the next code task.

## Updating the handoff

For the next task, record its scope, workstation or environment, branch, base and tested revision, and any working-tree changes included in testing. Note review findings and their disposition, essential checks passed or skipped with reasons, and any outstanding in-game checks. For a ZIP, record its path, source revision or working-tree state, and SHA-256. End with the next action and any decision that needs the owner.

## 2026-11-16 — Claude documentation review

- **Scope and baseline** — Revised the five agent workflow documents on `work-laptop/development`, based on `e5afb94`. Defined GitHub exchange, `main` integration, laptop branch ownership, and preservation of potentially newer home work.
- **Validation and artifact** — Checked documentation links and change scope. Lua and in-game checks were skipped for this documentation-only revision. No addon ZIP was produced.
- **Next action** — Inventory and preserve home-only work before any home pull, checkout, or merge. Use the published laptop branch to review this documentation independently.

## Handoff log convention

Append each dated entry at the end and preserve earlier entries. Correct past details in a new entry. Include environment, branch, base and tested revisions, review outcomes, checks and skips, and the next action. For a ZIP, include the full tested commit SHA, manifest version, filename or path, and SHA-256.

## 2026-11-24 — Phoenix public source and CurseForge candidate

The owner authorized GitHub synchronization and CurseForge preparation. The public release branch starts from origin/main at 8a54c0f51decc6df5496678ae1348ee17e3d0cee and imports the public Phoenix runtime from f3d18f1f8cf35a0ed99f4f838b3b9269642c5f72. The original Phoenix checkout remains on codex/phoenix-public. Existing remote branches are preserved.

The source branch excludes the officer companion implementation. Public alpha metadata replaces the private-test label without changing the 2.0.0-alpha.16 version. The public addon, TOC, assets, full-name fixes, native honor refresh and event protocols are carried from the tested Phoenix source. The CurseForge metadata requests Alpha and manual release. Live-client acceptance and final art redistribution review remain open.

The release manifest records the actual source commit and ZIP hash after the candidate has passed public regression and extracted-package checks.
