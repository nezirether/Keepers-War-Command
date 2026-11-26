# Changelog

## 2.0.5 (2026-11-26)

- Winter Veil 2026 seasonal War Room decorations (November 26 to January 2), with a Settings switch.
- See the [release notes](CURSEFORGE_CHANGELOG.md).

## 2.0.4 (2026-11-26)

- Officer companion compatibility is decided by an integration contract version, not the release number.

## 2.0.3 (2026-11-25)

- War Room Classic interface, World PvP flagship leaderboard, activity feed, Hot Zones, Guild SOS, grouped navigation and Guild Hall.
- Deletion authorization, clock-difference and display fixes.

## 2.0.0 (2026-11-24)

- Official stable release for WoW Forever 1.60.1. The distributed ZIP contains the public runtime previously tested as alpha.16.
- See the [release notes](CURSEFORGE_CHANGELOG.md) for the War Room, alerts, and guild coordination changes.

## 2.0.0-alpha.16 (public private test)
- Integrated Claude's ten event artwork plates with the current public War Celebrations system.
- Added a saved artwork toggle, ten-plate preview, theme-aware backing and reduced-motion-aware plate animation.
- Reflowed toast text, location and action rows and exposed local death pin/copy actions when coordinates exist.
- Added committed-asset validation to the public package gate.

## 2.0.0-alpha.15 (public private test)
- Removed the installation-based Open-world death leaderboard tab. Historical Lifetime opens first.
- Added celebration presentation policy, bounded priority queue, fade, reduced motion, previews, local killing-blow streaks and personal Chronicle.
- Refresh native honor immediately on login and world entry with bounded delayed retries.

## 2.0.0-alpha.14 (public private test)
- Resolve local kill and death names through the GUID-backed roster identity and reject full-name self echoes.
- Resolve verified rename aliases before filtering PvP rankings.
- Add bounded source-event deduplication to the shared toast presenter and source-ID CTA notices.

## 2.0.0-alpha.13 (public private test)
- Curated the public gallery to 13 designs in ten collections. All 100 historical IDs remain registered and saved choices resolve to visible designs.
- Integrated five reviewed batch packs. Preserved the existing flagship art and limited dashboard trim to an eight-unit strip.

## 2.0.0-alpha.12 (public private test, 2026-11-23)
- Added the eight Trogdor Studio v1 candidate textures to the public Trogdor skin for in-game testing.
- Adjusted the dashboard focal point upward after reviewing wide and narrow crops.

## 2.0.0-alpha.11 (public private test, 2026-11-23)
- Registered flagship art from a single validated designer manifest and added a public-package preflight.
- Added focal-point cropping for scenes and gallery previews. Retained the four existing illustrations and 100 approved skin IDs.
- Added shared motif emblems, material treatments and trim for controls across the catalog, and a larger in-gallery preview of the active skin.
- Separated several visually close catalog themes and rendered all 100 for comparison.
- Reserved more room for narrow ranked names and restored the full display name on hover in Guild Records.

## 2.0.0-alpha.10 (public private test, 2026-11-23)
- Added the official 100-skin gallery across ten collections, with searchable pooled previews, result ranges, paging, favorites, recent and applied filters.
- Added independent materials, trim silhouettes, heading faces and high-contrast palettes throughout the public War Room while preserving the four illustrated flagships.
- Verified each skin through the gallery controls and all public page routes.

## 2.0.0-alpha.9 (public private test, 2026-11-23)
- Added illustrated flagship packs for Trogdor, Horde, Alliance and Blood Moon. Classic and Sleek use shared graphics.
- Integrated themed headers, crests, dashboard art, alert treatments, ornaments and pooled gallery previews.
- Bounded the sidebar and title strip independently and gave navigation labels explicit anchors and selection feedback.

## 2.0.0-alpha.8 (public private test, 2026-11-23)
- Added the public Appearance Gallery with six presets, search, collection filters, favorite and recent lists, and full War Room previews that can be applied or canceled.
- Saved explicit appearance choices per character, with existing selections as the migration fallback.
- Added reusable artwork and optional client-font styles, opaque panels, and independent title, subtitle and score columns in Guild Records.

## 2.0.0-alpha.7 (public private test, 2026-11-23)
- Fixed disappearing War Room filter tabs by giving the shared toolbar's wrapped tab strip an explicit parent anchor after the toolbar is sized.
- Historical Deaths tabs select your own record on entry so the detail pane agrees with the leaderboard.

## 2.0.0-alpha.6 (public private test, 2026-11-23)
- Lifetime Deaths, Battleground Deaths and Non-Battleground Deaths read the native Forever Statistics API and use independent leaderboard tabs.
- Guild Records shares historical totals and the separate player-caused and raid/dungeon counts through its existing guild-scoped transport.
- KWC continues to record open-world death history separately, including available attackers, timestamps and locations.

## 2.0.0-alpha.5 (Phoenix public private test, 2026-11-23)
- Added persistent page navigation, shared list headings with paging and full-text hover, dashboard shortcuts, and jump controls in Alerts and Settings.
- Reflowed Raid Operations tabs and fixed embedded Raid Tools sizing while the War Room is resized.
- Preserved malformed WarSpoils history for review and stopped recovery pages at queue refusal.
- Checked Raid Tools group eligibility before decoding; retained the existing codec, framing and sync protocols.
- Expanded regression coverage for populated layouts, Guild Services withdrawals, and damaged or newer WarSpoils SavedVariables.

## 2.0.0-alpha.4 (Phoenix public private test, 2026-11-23)
- Guild Services now has separate crafter and recipe views, 12 profession categories, sorting, and publication feedback.
- Raid Operations adds a GUID-keyed WarSpoils ledger, confirmed manual awards, bounded recovery, and a separate policy preview.
- The dashboard shows recent recorded WarSpoils awards. World PvP distinguishes no-honor killing blows from honorable kills.
- Sync status distinguishes a pending recovery request from receipt of verified recovery data.

## 2.0.0-alpha.3 (public private test, 2026-11-23)
- Guild Services resolves shared recipes through the loaded GuildServices module and searches both spell and produced-item names.
- War Room toolbars wrap filters and actions to their available width. Board drawers share an action flow, and Alerts and Settings cards size to their controls and wrapped text.
- The Trogdor theme has a guild operations banner, a more legible palette, and a separate status row. Classic remains selectable. Window dimensions and effective scale adapt to the screen.
- Public-only packaging and regression checks cover populated professions, layouts at three dimensions, and public board and sharing flows.

## 2.0.0-alpha.2 (private test, 2026-11-23)
- Killing blows: reads Forever's `PARTY_KILL` for your own and your pet's kills, without the combat log. It names the victim for the honor path. Killing blows that earn no honor go to the guild as `WORLDKB`, with an opt-in popup under Alerts > Enemy slain.
- Research pass over the WAIE index and 21 reference add-ons (`docs/RESEARCH_FINDINGS.md`). No third-party code was copied.

## 2.0.0-alpha.1 (private test, 2026-11-23, superseded)
- New public interface, **The War Room**, built from scratch (no 1.x UI code or textures): left-rail navigation, status strip, 11 pages, Trogdor and Classic skins, resizable/remembered window, new minimap button.
- New toast popups for guildmate deaths, guild kills, bounty sightings, new Calls to Arms and Guild LFG, each with preview, move/lock, timing and sound settings.
- New officer add-on **KeepersWarCommand_Command** with the **Command Table** console. All recruitment moved out of the public add-on. Adds a 72-hour guild-wide whisper cooldown, permanent Do Not Contact, officer-only whisper sync, identity approvals, board administration and an audit log. Every officer action re-checks live guild rank; locked when the roster is stale, after a guild change or after demotion.
- **Character renames**: history now follows the character GUID. Verified renames move PvP, Guild Records, death counts, board authorship, responses, claims, raid sign-ups, attendance and services data to the new name; officers can approve links for renames that happened before 2.0.
- Own open-world deaths now record map coordinates (Drop Pin / Copy Coordinates).
- Sync engine, wire formats and SavedVariables (`KWCDB`) carried over from 1.8.2; 1.8.2 and 2.0 clients exchange boards (tested in simulation).
