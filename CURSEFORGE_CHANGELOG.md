# Keepers War Command 2.0.3: War Room Classic

For WoW Forever 1.60.1 (Interface 16001). Changes since 2.0.2.

## New look: War Room Classic

- Rebuilt War Room interface with Trogdor heraldry, new textures, buttons, icons and scrollbars.
- Redesigned Dashboard, navigation, Bounty Board and notification popups.
- Distinct Standard, Heroic and Legendary celebrations.
- Better window resizing and scaling. The minimap button follows window resizing correctly.
- War Room Classic replaces the older skins. The skin gallery has been removed.

## World PvP first

- World PvP is now the flagship leaderboard, with the Warlords of Trogdor honoring the top five. Battlegrounds and Lifetime HKs have plain ranking tables.
- Kill totals are easier to read, and out-of-date scores are labelled.
- The Dashboard adds a World PvP activity feed of the 25 latest events.
- PvP Hot Zones show where guild reports have clustered in the last 60 minutes.

## Guild SOS: Request Backup

- Send an urgent open-world call for backup that goes ahead of routine guild traffic.
- One active request per player, a 60-second cooldown and a 10-minute expiry with a countdown.
- Editing a request does not create a new call, and the send status says what actually happened.
- If the requester goes offline, an online officer running 2.0.3 publishes the expiry.

## Navigation

- The sidebar is grouped into War Room, Guild Support and Advanced, with PvP first.
- Guild Hall brings Guild LFG, Raids and Services together in tabs.

## Fixes and reliability

- Deleting a record now checks your verified guild identity and rank, and explains why a deletion is refused. `/kt deletediag` shows the details.
- Authorized officer announcements can appear as War Room notices.
- Better handling of clock differences between guild members.
- Corrected zone names in Hot Zones and a gap in the alert buttons.
- Removed two artwork controls that no longer did anything.
- Fixed Dashboard startup and texture display problems.

## Updating

Exit the game, back up the `KeepersWarCommand` folder and your SavedVariables, then replace the folder. Keep your SavedVariables. Restart the game rather than using `/reload`, because there are new texture files.

## Known limitations

- Guild SOS has no delivery confirmation.
- Guildmates on older versions may keep an offline player's request active until an updated officer is online, and may see extra popups when a request is edited.
- Free-text calls show no zone.
- Hot Zones counts each member's report, and its instance filtering uses English instance names.
- Kill and death logs keep the 75 latest entries.
- Alert positions saved by 1.x versions are not carried into 2.x.
