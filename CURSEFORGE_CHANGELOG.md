# Keepers War Command 2.0.0-alpha.16

This Alpha updates the public guild War Room for WoW Forever 1.60.1.

- Adds 13 curated appearance skins and ten event-specific alert illustrations.
- Gives death alerts separate rows for full character names, locations and buttons.
- Adds pin and copy-coordinate actions when a local death record has coordinates.
- Adds War Celebration levels, reduced motion, manual previews and a bounded notification queue.
- Adds observed killing-blow streak milestones and a personal War Chronicle.
- Adds explicit authorized CTA Victory, Objective completed and Withdraw outcomes.
- Shows native historical Lifetime, Battleground and Non-BG death rankings.
- Refreshes supported native honor statistics on login, reload and relevant updates.
- Resolves verified full names and historical aliases, with explicit event identities between updated clients.

Keep SavedVariables when updating. Back up the current addon and SavedVariables before installation.

Known limits include legacy clients' reports without unique event IDs, pending client verification of alert clamping, motion and sound, and unavailable attribution for personal completed-bounty and CTA-attendance milestones. Full details are in docs/CELEBRATIONS_ALPHA15.md and docs/ALERT_ART_MERGE_ALPHA16.md.

Automated validation passed 479 public checks per runtime on Lua 5.1 and LuaJIT at the Phoenix source checkpoint. The upload candidate receives its own source and package checks.
