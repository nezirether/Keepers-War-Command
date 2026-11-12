# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Keepers War Command (KWC) is a World of Warcraft addon for **WoW: Forever (Interface 16001)**, built for the guild Keepers of Trogdor. It is plain Lua 5.1 loaded by the WoW client: no build step and no package manager. Slash commands: `/kwc`, `/kt`, `/keepers`. GitHub: `nezirether/Keepers-War-Command`.

## Repository layout: check where you are first

This checkout (`D:\KeepersWarCommand`, branch `main`) is **not where active development happens**. `main` here is a stale v1.5.0-dev.15 snapshot (`origin/main` is 26 commits ahead). The root also holds release/test zips, CurseForge changelog drafts and audit reports. These are untracked artifacts, so don't commit them.

Real work happens in sibling **git worktrees** (`git worktree list`). The most current one is:

- `D:\KeepersWarCommand-ui2`, branch `dev/ui-2.0`, version 1.8.x. It has `tests/`, `CHANGELOG.md`, `CURSEFORGE_*.md`, `INSTALLATION.md`, `design/UI2`, and `development/` (UI2 plans).

Other worktrees cover release branches (`release/1.6.0-alpha.1`), hotfixes (`codex/1.7.1-death-attribution`), maintenance (`dev/1.6.1-maintenance`) and detached verification checkouts. Before you edit anything, confirm which branch or worktree the user means.

Shipping is done by zipping the `KeepersWarCommand/` addon folder. Names follow `KeepersWarCommand-<version>[-<Feature>_Private_TEST].zip`. Bump `## Version` in the `.toc` and `KWC.version` in `Core.lua` together.

## Architecture (current 1.8 line)

- **Load order is the `.toc` file.** Every file shares the global `KWC` table, usually aliased `local K=KWC`. `Core.lua` loads first and defines the shared helpers: `K.Say`, `K.Clean` (sanitizes `|`, CR and LF and truncates), `K.Log`, `K.IsOfficer`, name normalization and roster/guild identity. Later files hang their modules off `K`. `UI.lua`, the launchers and `RaidToolsHost.lua` load last.
- **Event bus:** `K.On(event, fn)` registers WoW events on one shared frame and fans them out to listeners. Use it instead of creating a new event frame for each module.
- **Persistence:** SavedVariables `KWCDB` holds the main addon data. Raid Tools adds `KeepersRaidToolsDB`, `KeepersRaidToolsAttendanceDB`, `KeepersRaidToolsRosterDB` and `KRTForeverNotesDB`. Shared datasets should be scoped to guild identity (`K.GuildScope`).
- **Networking:** all guild addon traffic goes through `Network.lua` (`K.Net.Send`), a throttled, deduplicating queue. Messages are capped at 250 bytes, the queue at 350 entries, and `RECOVERY` priority traffic has its own budget. Each feature registers its own prefix. Board sync uses `KWC3` (legacy) and `KWC4` (revisioned snapshots and tombstones, in `Sync.lua`/`Operations.lua`). GuildLFG, GuildRecords, GuildServicesSync, RaidCommand, RaidSignup and AddonChecker each have their own prefix.
- **Trust model:** there is no cryptographic authentication. Receivers rely on the WoW-delivered sender, the channel (GUILD/RAID/PARTY) and local roster or officer-rank checks. Incoming handlers must validate the sender's authority, freshness or revision, and field bounds, and must sanitize text (no control characters, delimiters or `|` markup). `KWC_Guild_Synchronization_Audit_086f382.md` lists the known weaknesses: relay forgery, stale replays, missing tombstones, and an absent guild namespace.
- **Raid Tools** (`Modules/RaidTools/`) is an embedded fork of Purplexity Raid Tools by nivthefox, with Ace libraries under `Libs/` (AceComm, LibSerialize, LibDeflate). `RaidToolsBridge.lua` and `RaidToolsHost.lua` connect it to KWC. Boss data goes in `BossData/<Instance>/`, and each new boss file has to be added to the `.toc`.
- **Forever API caveats:** guard Forever or retail APIs with `pcall` or existence checks, and respect `issecretvalue`. Restricted combat-log APIs are deliberately not used; for example, death attribution uses `C_DeathRecap` and fails closed. Protected actions such as guild invites must run from hardware-click handlers.

## Tests

Tests live in `tests/*.lua` in the dev worktrees. They are standalone Lua 5.1 or LuaJIT scripts that stub the WoW API, load the real addon files, and drive their event and message handlers. Run them **from the worktree root** because they use relative paths like `KeepersWarCommand/Core.lua`. Many also `loadfile("tests/guild_sync_audit.lua")` (a simulated multi-client guild network) and call `git show <commit>:...` to get baseline sources, so they need the git history.

No `lua` binary is on PATH. A Python `lupa` build (Lua 5.1 and LuaJIT, cp312 wheels) is vendored at `D:\KeepersWarCommand\DEV56-work-_rvk1qop\validation-deps`. It needs **Python 3.12**. The `python` on PATH is only the Windows Store stub, and `C:\Python314` won't load the cp312 wheels, so use the Codex-bundled 3.12. To run a single test (from Git Bash):

```sh
P=/c/Users/jerry/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe
cd /d/KeepersWarCommand-ui2
$P -c "import sys; sys.path.insert(0, r'D:\KeepersWarCommand\DEV56-work-_rvk1qop\validation-deps'); import lupa.lua51 as l; l.LuaRuntime().execute(open(sys.argv[1]).read())" tests/battle_res.lua
```

A test prints `PASS: ...` when it succeeds and fails by raising an error through `assert`/`error`. `tests/guild_sync_release_gate.lua` holds the current sync release criteria.
