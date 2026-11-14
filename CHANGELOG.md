# 1.7.0 (UI 2.0 private test)

- Added the Alert Command Center with an alert card list, a focused configuration pane, existing artwork, and local popup previews.
- Added the Command Center, a shared graphite and crimson theme, and direct links to guild tools.
- Added local Settings Search with categories and links to the existing controls.
- Refreshed the PvP boards, Raid Operations, Guild LFG, Guild Services, recruitment, roster, Addon Checker, and sync diagnostics.
- Spelled out Call to Arms across player-facing navigation, settings, and table labels.

# 1.6.1 (Private test)

- Added Home shortcuts, simplified sidebar headings, and added tooltips for shared actions and settings.
- Added a Trogdor minimap launcher with saved visibility and position controls.
- Enabled Guild Services sharing once per character after verification, with an opt-out in Preferences.
- Made the Battle Resurrection indicator raid-only, with an off default for new installations and existing preferences retained.

# 1.6.0-alpha.1

Development testing for WoW Forever 1.60.1.

- Added Guild LFG with filters, listing management, interest, invitations, and guild-scoped recovery.
- Added Guild Services with a guild roster, searchable professions and observed recipes, and opt-in sharing.
- Unified guild readiness across LFG and Guild Services. Added Retry and /kwc guilddebug. Addon Checker reports the local version without requiring a reply.
- Added /kwc as the primary alias alongside /kt and /keepers.
- Updated Bounty Board controls, alert artwork and positioning, and death attacker attribution when Forever exposes usable recap data.
- Added separate lifetime, World PvP and Battleground rankings. Improved roster identity matching and separated Sync Health board, PvP and transport counters.
- Consolidated Raid Operations, repaired Raid Notepad, and added ordered raid assignment snapshots and revisioned readiness.
- Hardened guild-scoped persistence, authorization and stale replay handling. Added bounded officer recovery for supported guild records.

Automated tests cover these paths. Broader live verification of guild recovery, LFG, recipe collection and sharing is pending. Use compatible clients for shared features.
