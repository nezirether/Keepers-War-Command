# Keepers War Command 2.0

Keepers War Command is a guild War Room for World of Warcraft Forever 1.60.1, Interface 16001.

The public addon includes Calls to Arms, bounties, guild groups, Guild Services, Raid Operations, WarSpoils, historical PvP and death rankings, theme-aware alerts, personal commendations and 13 curated visual skins.

Open the War Room with /kt. Use /kt help for commands.

## Current build

2.0.0-alpha.16 is an Alpha candidate. Native client rendering, alert edge clamping, sound and multiplayer packet timing require live acceptance. See CURSEFORGE_UPLOAD_INFO.md and docs/ALERT_ART_MERGE_ALPHA16.md.

## Install and update

Exit Forever, back up the addon and SavedVariables, then replace the KeepersWarCommand folder with the one in the ZIP. Keep SavedVariables when updating. See INSTALLATION.md.

## Public checks

Run tests/run_all.sh --public-only with Lua 5.1, luac5.1 and LuaJIT available. The package tools verify the committed public TOC and artwork before creating a ZIP.

## Provenance

This branch imports the public Phoenix source from f3d18f1f8cf35a0ed99f4f838b3b9269642c5f72 onto the existing GitHub main history. The original workstation checkout and historical GitHub development branches are preserved. Public runtime files exclude the officer companion.

Raid Tools retain their attribution and bundled library licenses. See KeepersWarCommand/THIRD_PARTY_NOTICES.txt.
