# Keepers War Command 2.0

Keepers War Command is a guild War Room for World of Warcraft Forever 1.60.1, Interface 16001.

The public addon includes Calls to Arms, bounties, guild groups, Guild Services, Raid Operations, WarSpoils, historical PvP and death rankings, theme-aware alerts, personal commendations and 13 curated visual skins.

Open the War Room with /kt. Use /kt help for commands.

## Current build

**Keepers War Command 2.0.0** is the official stable release for WoW Forever 1.60.1.

- [Download on CurseForge](https://www.curseforge.com/wow/addons/keepers-war-command/files/9793652)
- [GitHub release and mirror ZIP](https://github.com/nezirether/Keepers-War-Command/releases/tag/v2.0.0)

The November 24, 2026 CurseForge ZIP retains the internal version `2.0.0-alpha.16`. See the [release record](CURSEFORGE_UPLOAD_INFO.md) for the checksum and source provenance.

## Install and update

Exit Forever, back up the addon and SavedVariables, then replace the KeepersWarCommand folder with the one in the ZIP. Keep SavedVariables when updating. See the [installation and rollback instructions](INSTALLATION.md).

## Public checks

Run tests/run_all.sh --public-only with Lua 5.1, luac5.1 and LuaJIT available. The package tools verify the committed public TOC and artwork before creating a ZIP.

## Provenance

This branch imports the public Phoenix source from f3d18f1f8cf35a0ed99f4f838b3b9269642c5f72 onto the existing GitHub main history. The original workstation checkout and historical GitHub development branches are preserved. Public runtime files exclude the officer companion.

Raid Tools retain their attribution and bundled library licenses. See KeepersWarCommand/THIRD_PARTY_NOTICES.txt.
