# UI 2.0 implementation plan and feature parity inventory

The base is d29369a9646a31fa22924e99a25964f038d4578c on dev/1.6.1-maintenance. The committed private 1.6.1 archive passed 19 suites, 111 Lua 5.1 syntax checks, and 79 TOC checks. All 19 baseline suites passed again from the isolated worktree. Target 1.7.0 for private testing, following the completed 1.6.1 maintenance source.

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

## Parity and live client checks

- The settings catalogue links to existing controls and feature sections. Search and filtering use session-local state. Native Raid Tools retain their original settings controls. Resets use existing APIs and require confirmation for the Battle Resurrection and Smart Mode sections.
- Settings search, full Call to Arms labels, layout callbacks, minimap interactions, and the production TOC load path are covered by the automated suites. Existing tests exercise guild readiness, LFG flows, roster matching, recruitment, alerts, raid forms, and synchronization handlers.
- Check actual clipping and tooltip placement at a small and normal UI scale, with long guild names and large rosters. Exercise window dragging, scroll interactions, combat entry and exit, minimap clicks, and the existing popup previews in Forever.
- Verify explicit board actions, guild sharing, LFG invites, Raid Operations, and version reports with real players running compatible builds. Confirm the saved settings and identity behavior after reload or a guild switch.

## Phase 0B — Concept art and approval

The previously packaged UI 2.0 build at `8e2e79e` is the comparison build. The owner approved the [design package](../design/UI2/README.md) on November 13, 2026. The eight full-window concepts, tokens, and component states guide this revision.

Review Command Center, Settings Center, Alert Command Center, War Room, Bounty Board, Guild LFG, Guild Services, and Raid Operations. Use a dark graphite and blackened steel shell, deep crimson selection, muted bronze headings, and readable off-white body text. Use the original Trogdor mark and existing alert artwork as references. The concepts use illustrative records and settings to demonstrate the layouts.

## Phase 4B — Alert Command Center

Add a dedicated Alerts destination within Settings Center. Cards show the alert name, purpose, effective state, and a Configure action. Keep display state and sound state distinct. Offer a local test for Guild Death and Bounty Spotted. Show why an action is unavailable when a module or required context is missing. Link existing pages and search results to the relevant card or configuration.

| Existing alert | Configuration and test scope |
| --- | --- |
| Guild Death | Popup, sound, size, duration, position, chat alerts, combat suppression, guild broadcast, and Smart Mode including threshold, detection window, quiet period, and its existing reset. Test via the local death preview. |
| Bounty Spotted | Popup, sound, size, duration, position, and existing friendly bounty test mode. Test via the local bounty preview. |
| Calls to Arms and report reminders | Separate cards linking to their existing local chat settings. No positioning controls or live event tests. |
| Guild LFG notices | Link existing interest, invitation, and matching notification controls. No positioning controls or live event tests. |
| Raid alerts and displays | Link Ready Check notifications, Death Protection, and existing combat display settings, including Battle Resurrection. Retain their native controls and permissions. |

Keep the existing global alert sound option. Omit sound selection, per-alert volume, and appearance controls where the current APIs do not expose them. Reuse existing alert artwork and the current scale, duration, and positioning ranges.

For Guild Death and Bounty Spotted, use the existing unlock and preview path for **Move Alert**. Show a positioning message with drag and lock instructions, save through the existing drag-release mechanism, and use the existing Reset Position call. The configuration pane should show the current values and update immediately. Retain confirmation only where the existing section reset calls for it. Use readable toggles, optional tooltips, and clear disabled states.

Use only local presentation for tests. Verify that previews send zero guild messages, create zero synchronization records, and leave gameplay and PvP statistics alone. If an alert has no safe preview, omit the test action or show a clearly labeled presentation-only sample. Never use a live trigger to test.

### Approval and protection

Keep edits in presentation code. Preserve detection, combat-log handling, death and bounty processing, dispatch, synchronization, networking, authorization, existing defaults, and SavedVariables schema. The concept directory stays outside the packaged addon. No automatic publishing, merging, or release.

The implementation layers the approved palette and alert cards onto the existing UI 2.0 window and feature screens. The position pane displays the stored coordinates or default placement and uses the current popup for actual drag testing. Guild LFG and raid cards link to the corresponding feature pages. The current window saves its scale and keeps its drag position while the frame is loaded. Cross-session main-window position persistence would require additional storage and is outside this revision.
