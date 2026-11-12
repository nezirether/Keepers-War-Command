# Phase 1: System Discovery (read-only)

Collected on 2026-11-19 by Claude Code, ahead of the reinstall on 2026-11-21/22. Nothing was copied, moved or changed. The only writes were this folder and a dry-run log in %TEMP%.
Status: **NOT READY TO WIPE**. No backup exists yet outside the internal drives.

## 1. Hardware and Windows

| Item | Verified value |
|---|---|
| OS | Windows 11 **Home**, build 26300, 64-bit, installed 2026-02-27 |
| Activation | Licensed, **OEM:DM** (key embedded in firmware). Should reactivate automatically on the same motherboard |
| BitLocker / Device Encryption | Shell reports protection **off (0)** on C:, D:, E: and F:. `manage-bde` needs admin, so this is **not admin-verified**. Check Settings > Privacy & security > Device encryption yourself |
| Board / CPU / RAM | ASRock A320M-HDV R4.0 · Ryzen 5 5500 · 15.9 GB |
| GPU | AMD Radeon RX 6600, driver 32.0.21045.29003 (dated 2026-11-16) |
| Black-screen diagnostics | `C:\Windows\Minidump` is empty. No dxdiag, msinfo or black-screen reports were found in Desktop, Documents, D:, E: or F: |

### Disks (physical to letter mapping, verified)

| Disk | Model | Bus | Size | Letter / label | FS | Free | Fate |
|---|---|---|---|---|---|---|---|
| 0 | ADATA SU630 SSD | SATA | 447 GB | **C:** "Windows" (boot/system) | NTFS | 38.5 GB | **WIPED** |
| 1 | WDC WD10EZEX HDD | SATA | 931 GB | **D:** "1TB HDD" | NTFS | 576.8 GB | **WIPED** |
| 2 | "VendorCo ProductCode" USB | USB | 14.6 GB | **F:** (no label) | **FAT32** | 13.1 GB | survives |
| 3 | "VendorCo ProductCode" USB | USB | 14.6 GB | **E:** "AI-DEV" | exFAT | 10.5 GB | survives |

D: is the HDD. E: and F: are the two flash drives. Both flash drives report a generic "VendorCo ProductCode" controller, a pattern common to fake-capacity drives, so a write and read-back verification after a replug is mandatory.

## 2. AI tooling inventory

| Tool | Version | Location(s) | Size | Notes |
|---|---|---|---|---|
| Claude Desktop (MSIX) | 5.11492.5.0 | Data: `%LOCALAPPDATA%\Claude-Data\claude_pzs8sxrjxfjjc` (redirected; `%APPDATA%\Claude` absent) | 418 MB (355 MB is the bundled CLI binary, the rest mostly cache) | `config.json` holds `oauth:tokenCache` and is **EXCLUDED** |
| Claude Code CLI | 2.1.326 | `~\.local\bin\claude.exe`, `~\.claude` (61 MB), `~\.claude.json` (167 KB) | | Memory dirs exist for: AI-Orchestrator, AI-Orchestrator-p-source, KeepersWarCommand, KWC-Rebirth, WarCommand, WAIE, Shaggy Ink Farms. `.credentials.json` and `sessions\*.key` are **EXCLUDED** |
| Codex Desktop + CLI | app 26.1111.9265.0, cli 0.169.0 | `~\.codex` (3.27 GB), `%LOCALAPPDATA%\OpenAI\Codex` (859 MB of binaries and runtimes), `~\.cache\codex-runtimes` (1.38 GB) | | `auth.json` and `.sandbox-secrets` are **EXCLUDED**. SQLite DBs (thread_history 82 MB, logs 66 MB) are **live** and can only be copied after Codex exits. 20 Codex project workspaces sit in `~\Documents\Codex` (7.6 GB) |
| Ollie-AI (AI-Orchestrator) | git repo, no remote | `D:\AI-Orchestrator` (912 MB; 791 MB of that is task worktrees), `%LOCALAPPDATA%\AI-Orchestrator\tasks` (446 task files) | | **Not running and no scheduled tasks** (verified). `config.json` has `autonomous.enabled = true`. Disable it in the restored copy before you ever run `ai.ps1` |
| Git | 2.54.0 + git-lfs filter | `~\.gitconfig` | | user.name nezirether |
| GitHub CLI | 2.104.0 | token is in the OS keyring, not in hosts.yml | | re-run `gh auth login` |
| GitHub Desktop | installed | `%APPDATA%\GitHub Desktop` (20 MB) | | |
| Node / npm | 24.16.0 / 11.13.0 | | | |
| PowerShell | 7.7.0 (Store) | no profiles found | | |
| VS Code | 1.146.0 | `%APPDATA%\Code\User` | | |
| Python | **only the Store stub on PATH**. `py` points to a missing `C:\Python314` | Codex-bundled 3.12 at `~\.cache\codex-runtimes\...\python.exe` (used for the KWC lupa tests) | | Python 3.12 needs reinstalling |
| MCP | Claude: none user-defined in `.claude.json`. Codex: `node_repl` plus the GitHub connector | | | The `plugin:github` MCP failed auth in this session |
| Skills | Claude: synced cloud skills only. Codex: 5 system skills, 1 rules file | | | No custom local skills found |

Full list of installed programs (197): `inventory/installed-apps.txt`.

## 3. Project locations and Git state

Git counts were collected without a fetch, so they are relative to each repo's **last fetched** remote state. Full table: `inventory/git-inventory.csv`.

| Priority | Project | Path(s) | Remote | Local-only risk |
|---|---|---|---|---|
| P0 | **Keepers War Command** | Common repo `D:\KeepersWarCommand\.git`, with **56 worktrees** (ui2, kwc2-codex, dev56-recovery, 11 under `D:\keepers old`, 41 under `D:\AI-Orchestrator\worktrees\KWC`) | github nezirether/Keepers-War-Command | **106 commits on no remote, 51 local branches**, 106 untracked artifacts in the main checkout, uncommitted edits in 4 Ollie worktrees and in dev56-recovery |
| P0 | KWC work-laptop line | `E:\AI-DEV\Projects\KWC-WorkLaptop-1.8` (+2 worktrees), `E:\AI-DEV\Projects\KeepersWarCommand` | **none** | **74 commits with no remote**. Only copy is on USB E: |
| P0 | **WarCommand** | `D:\WarCommand` (+9 Ollie worktrees, `D:\AI-Orchestrator\p\source` clone) | **none** | 7 commits and 10 branches exist only here |
| P0 | **WAIE** (WoW-Addon-Intelligence-Engine) | `D:\WoW-Addon-Intelligence-Engine` (1.1 GB, mostly `knowledge\`) | **none** | 3 commits on no remote, 29 untracked |
| P0 | **Ollie-AI** | `D:\AI-Orchestrator` | **none** | 1 commit on no remote, 9 modified files, 6 untracked |
| P1 | KWC-Rebirth | `D:\KWC-Rebirth` | **none** | 13 commits on no remote |
| P1 | MacroForgeAI | `D:\MacroForgeAI` (+ `-stress-1000`) | **none** | 5 commits on no remote |
| P1 | TrogdorWarKommand, KWC-Hub, KWC Addon Research | `D:\…` | not git | folder copy only |
| P1 | **GuildRadioFM** | `~\OneDrive\Documents\GuildRadioFM` (clean), `C:\GuildRadioFM` (addon files), `F:\2026-11-18\grf\work\GRFM` (branch ui/readability-ui6, 5 branches) | github nezirether/GuildRadioFM | F: copy is USB-only. Release zips are on F: and E: |
| P1 | ProfessionEase | zips and handoff docs on `F:\` only | n/a | USB-only |
| P2 | KeyStoneCouncil | `C:\Projects\KeyStoneCouncil`, OneDrive copy | github | clean, pushed |
| P2 | Shaggy Ink Farms website | `D:\Users\jerry\JB Ventures\Shaggy Ink Farms\Website` | github | **1 stash** |
| P2 | Codex workspaces | `~\Documents\Codex\2026-05-28 … 06-17` (7.6 GB) | mixed | several untracked trees, 1 unpushed commit (publish2) |
| P2 | "death counter" | `~\OneDrive\Documents\ChatGPT\death counter` | none, 0 commits | 28 untracked files (OneDrive-synced) |
| — | The Last Deathknell, SixProductStudio, Practical_AI_Studio | `E:\AI-DEV\Projects\…` | n/a | USB-only |
| — | WoW SavedVariables | `D:\World of Warcraft\_forever_\WTF` (32 MB, account REBEL652) + older copy `~\Desktop\WTF` | n/a | **must back up** (KWCDB, Raid Tools DBs) |

Agent knowledge found: CLAUDE.md and AGENTS.md in KWC-ui2, KWC-kwc2, WarCommand, WAIE and AI-Orchestrator/p/source. Handoffs: `D:\AI-Orchestrator\backups\EndOfDay-*\TOMORROW-HANDOFF.md`, `USB_WORKFLOW_HANDOFF.md`, `E:\AI-DEV\Task-Handoffs\CHATGPT_HANDOFF_2026-11-17.md`, F:\ GRFM/ProfessionEase handoffs, and 5 Ollie `recovery.md` task files. E: already holds an earlier `AI-DEV` layout (Agent-Knowledge, Task-Handoffs, Projects, Backups).

## 4. Backup size estimates

| Tier | Contents | Size |
|---|---|---|
| **T1 dev (dry-run measured)** | All P0/P1 projects with full `.git`, Ollie and its task state, Claude/Codex config, sessions and memories (secrets excluded), WoW WTF and own addons | **2.81 GB / 22,998 files**. Add about 0.16 GB of Codex SQLite after Codex exits, plus about 0.1 GB of git bundles, for **≈3.1 GB** |
| T2 dev extras | `~\Documents\Codex` 7.6 GB · `D:\archonapp` 0.32 GB (an app beta, probably re-downloadable) · JB Ventures 0.85 GB · GRFM volume addons 1.2 GB (duplicated as zips inside WAIE) | ≈10 GB |
| T3 personal (**not AI-dev, but destroyed by the wipe**) | `D:\Home Photos` 9.83 GB · `D:\Family Photos` 1.04 · `D:\2022 summer photo session` 0.68 · `D:\Jackie_Mcdonell…` 0.27 · personal PDFs and resumes in D:\ root · `~\Desktop\deal with later` 7.5 · Desktop loose 1.9 · `~\Videos` 17.2 · `~\Saved Games` 0.1 | ≈38 GB |
| Already off-machine | OneDrive 2.7 GB (cloud-synced, **sync completeness not verified**), GitHub remotes | — |
| Re-downloadable (skip) | Games, SteamLibrary, WoW client, AddOns other than our own, installers in D:\ root (≈15 GB), Codex/Claude binaries | — |

USB free space in total: **23.6 GB** (E 10.5 + F 13.1).

## 5. Risks and blockers

1. **Capacity**: T1 fits twice. T1 + T3 does not fit, and personal photos and videos (≈30 GB) have **no destination**. This is a blocker if you want them kept.
2. **USB-only data**: E: holds the only copy of KWC-WorkLaptop (74 local commits), Ollie EndOfDay snapshots and The Last Deathknell. F: holds the only copy of the GRFM rc builds and ProfessionEase. Losing one stick loses that data, so cross-copy E to F and F to E.
3. **Generic flash drives**: the controller is a possible fake-capacity type. Verify by re-hashing **after unplugging and replugging** so the OS cache can't mask corruption.
4. **F: is FAT32**: 4 GB per-file limit (largest T1 file is 229 MB, so it's fine), 2-second timestamps, no ACLs.
5. **Many local-only repos** (WarCommand, WAIE, Ollie, KWC-Rebirth, MacroForgeAI, KWC-WorkLaptop, plus 106 KWC commits): GitHub is not a backup for any of them. Optionally push them to new **private** GitHub repos (needs your approval).
6. **Live data**: Codex (running) has WAL-mode SQLite open, and the Claude Code session in use right now writes to `~\.claude\projects`. Copy these after both apps exit.
7. **Absolute worktree paths**: worktree `.git` files point to `D:/KeepersWarCommand/.git/worktrees/...`. Restore to identical paths or run `git worktree repair`.
8. **Ollie auto-mode**: `autonomous.enabled=true` in config. The restore guide must disable it before the first run.
9. **Secrets** (excluded from all backups; you will sign in again): `~\.claude\.credentials.json`, `~\.claude\sessions\*.key`, `~\.codex\auth.json`, `~\.codex\.sandbox-secrets`, Claude-Data `config.json`, `Local State`, `Network\Cookies` and `Trust Tokens`. A regex scan of all T1 project and session text for GitHub, Anthropic, OpenAI and AWS tokens and private keys found **none**.
10. **Unverified**: BitLocker (needs admin), OneDrive sync state, GitHub ahead/behind (no fetch done), whether OEM reactivation succeeds after an SSD wipe (normally it does with a digital license).
11. No encryption tool is installed (7-Zip is absent), so Google Drive uploads would need `winget install 7zip.7zip` first.

## 6. Proposed destinations and exact operations (awaiting approval)

All operations use `scripts/Backup-Tier1.ps1`: robocopy `/E /COPY:DT /DCOPY:T /R:1 /W:1 /XJ /FFT`, **no** `/MIR`, `/PURGE` or `/MOV`, secrets excluded by name, layout `<Dest>\Files\<Drive>\<original path>`. The script also writes git bundles (`--all`, including stash) with `bundle verify`, a per-repo git-state report, and a SHA-256 manifest compared against each source file.

| Step | Operation | Dest | Size | Free after |
|---|---|---|---|---|
| A | Close Codex Desktop, then `Backup-Tier1.ps1 -Dest E:\PCBK-2026-11 -Execute` | E: | ≈3.1 GB | ≈7.4 GB |
| B | `Backup-Tier1.ps1 -Dest F:\PCBK-2026-11 -Execute` (second independent copy) | F: | ≈3.1 GB | ≈10.0 GB |
| C | Cross-copy USB-only content: `E:\` existing (4.1 GB) to `F:\PCBK-2026-11\USB-E-mirror`, and `F:\` existing (1.5 GB) to `E:\PCBK-2026-11\USB-F-mirror` | both | 5.6 GB | E ≈5.9 / F ≈5.9 |
| D | Unplug and replug both sticks, re-verify all SHA-256 manifests, restore-test into `%TEMP%\PCBK-restore-test` (clone from bundles, run one KWC Lua test) | — | — | — |
| E (optional) | Install 7-Zip, create an AES-256 `.7z` of T1 with **your** passphrase (never stored in files), and upload it to Google Drive as an off-site third copy | Google Drive | ≈2 GB | — |
| F | Personal T3 data: **needs your decision** (larger external drive, Google Drive capacity, or accept the loss) | ? | ≈38 GB | — |
| G | After you exit Claude: manual copy of `~\.claude\projects` (the live session) | E: and F: | <50 MB | — |
