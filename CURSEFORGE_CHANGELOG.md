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
