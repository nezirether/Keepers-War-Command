# UI 2.0 implementation plan and feature parity inventory

The base is d29369a9646a31fa22924e99a25964f038d4578c on dev/1.6.1-maintenance. The committed private 1.6.1 archive passed 19 suites, 111 Lua 5.1 syntax checks, and 79 TOC checks. A separate baseline replay is running from the UI worktree. Target 1.7.0 for private testing, following the completed 1.6.1 maintenance source.

| Screen | Existing actions and destinations to retain |
| --- | --- |
| Home and Guild Overview | Group finder, War Room, Raid Operations, Guild Services, Preferences, Overview, active operation links, Scout Network, Raid Command, Bounty Board, Sync Health |
| War Room, Scout Network, After Action, World PvP Deaths, Chronicle | Commander and lieutenant tools, operation and scout summaries, scout report, after-action draft, alert test, bounty prefill, recorded history |
| Calls to Arms | Create, edit, roster, RSVP and response, assignment, priority, status transitions, report, export, attendance, delete |
| Bounties | Create, capture target, selection, filters, details, sightings and sighting history, claim and approve, complete, cancel, reopen, edit, delete, announce and export |
| PvP Leaderboard and Achievements | Lifetime HKs, World PvP, Battlegrounds, refresh honor, rankings and tiers, achievement filters and pagination |
| Raid Operations and mounted tools | Overview, Raid Command, Sign-Ups, Attendance and editor, Roster and manager, Notes, Readiness and advanced settings, Invites and advanced settings, Combat and advanced settings, Battle Resurrection, Death Protection |
| Guild LFG | Browse, create, my listings, filters, matching and interest notices, select, edit, renew, close, delete, express and withdraw interest, whisper and invite |
| Guild Services | Overview, Professions, Recipes, directory refresh, sharing, search and sorting |
| Recruitment and Commendations | WHO range, candidate list, draft whisper, draft invite, ignore, history, commendation actions |
| Guild Roster and Addon Checker | Roster refresh, check versions, installed and peer status, local filtering, age and compatibility |
| Settings, Alerts and Sync Health | Window scale, minimap visibility and reset, guild sharing, report reminders, all sound and alert controls, death Smart Mode, Battle Rez widget and raid settings, explicit sync, diagnostics, checker and roster |
| Slash and entry points | /kwc, /kt, /keepers, named page routes, minimap click and right-click, player context entry points |

Use the bundled WoW font and native widgets. Centralize presentation tokens, improve window and Home layout, and link searchable settings to the existing controls. Verify scrolling and focus without adding setting storage. Keep explicit announcement and synchronization callbacks intact. Confirm supported resets through their existing APIs.

Core events and guild identity, Network, Sync, Operations, PvP, RaidCommand, RaidSignup, GuildLFGModel, GuildServicesSync, AlertFrameControls, death detection and all authorization and storage code are protected. Mixed UI files may change in drawing code only. The version string and TOC metadata are release bookkeeping.

Review each UI diff against this inventory. Run feature and security suites on the final commit, then verify the private ZIP against committed blobs. Live Forever layout, UI scale, drag, popup rendering, combat state and multiplayer behavior still require in-game checks.
