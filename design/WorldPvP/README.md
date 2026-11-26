# World PvP flagship leaderboard (private development build lb.1)

Private checkpoint on branch `private/worldpvp-leaderboard`. Not published and not
pushed. The addon version stays `2.0.2` (`## X-Build` marks lb.1) because the
officer companion requires public KWC `2.0.2` exactly.

## Changelog

- World PvP is the default flagship board and now carries the Warlords of
  Trogdor recognition, which was removed from Lifetime HKs.
- Ranks 1-5 are Warlords of Trogdor: rank 1 legendary, ranks 2-3 epic, ranks 4-5
  elite. Rank 6 and below use the blackened steel row. A player needs at least
  one World PvP honorable kill to be named a Warlord.
- Hero art: the title plate in short windows, the Warlords banner when the page is
  at least 560 units tall. All five Warlords fit at the minimum 900x560 window.
- New textured board tabs with icons and selected, pressed, hover and idle art.
- Battlegrounds and Lifetime HKs are plain ranking tables under a small crest.
- Kill totals are grouped (1,234,567). Stale scores are labelled. Search with no
  match has its own empty message.
- The old relative-score bar is gone from this page.
- No change to the PvP engine, network protocol, sync, or SavedVariables.

## Files

| File | Change |
| --- | --- |
| `UI/Pages/Leaderboards.lua` | rewritten presentation |
| `Media/WarRoomClassic/WorldPvP/*.tga` | 17 new textures |
| `KeepersWarCommand.toc` | `X-Build` label only |
| `tools/worldpvp_art.py` | rebuilds textures from the supplied pack |
| `tools/worldpvp_preview.py` | offline layout previews |
| `tests/world_pvp_board.lua` | new focused test |

Earlier artwork stays in place for rollback. The leaderboard page no longer draws
it, so old and new art cannot overlap there. Guild Records is unchanged.

## Texture inventory

Source: `KWC_WorldPvP_TexturePack_v1.zip`. All are 32-bit uncompressed TGA with
power-of-two sizes. Checksums are in `INVENTORY.json`.

| Texture | Size | Used for | Adaptation |
| --- | --- | --- | --- |
| WorldPvP_Header | 1024x256 | World hero, short window | none; drawn at 5:1 |
| Warlords_Banner | 1024x256 | World hero, tall window | none; drawn at 5:1 |
| KWC_Crest | 1024x256 | secondary board branding | none |
| Tab_Selected / Active / Hover / Inactive | 256x64 | tabs, three-slice | none |
| Row_Legendary / Epic / Elite | 1024x64 | Warlord rows, three-slice | leftover laurel fragments removed (x 36-219) |
| Row_Standard | 1024x64 | rank 6+ and unranked | none |
| Emblem_Legendary / Epic / Elite | 128x128 | Warlord rank emblems | dark backing made transparent |
| Icon_WorldPvP / Battlegrounds / Lifetime | 128x128 | tab icons | dark backing made transparent |
| Icon_Deaths | 128x128 | **not shipped** | there is no deaths board on this page |

The pack's header and banner look stretched to 4:1 compared with the concept art,
so they are drawn at about the concept's 5:1.

## Test results

Run on Lua 5.1.5; the first two suites below also pass on LuaJIT.

- `world_pvp_board`: 85 passed, 0 failed (sorting, top five, tiers, search, stale,
  empty, tabs, three window sizes, widget reuse, texture paths and formats)
- `ui_layout`: 71 passed
- `identity_rename` 27, `alerts` 27, `warspoils` 22, `killing_blows` 15,
  `name_echo` 11: all passed
- Lua 5.1 syntax: 158 files, 0 errors; no new global writes

These suites already failed on the untouched baseline and fail the same way now:
`kwc_load` (expects an alpha version string), `board_sync` (1 guild-ID check),
`public_features`, `historical_deaths`, `celebrations`, `appearance_gallery`,
`alert_art`, `alert_layout` (removed theme APIs), `phoenix_integration` (1 scroll
check), and `pvp_leaderboard` (old file paths). The older guild-sync scripts also
do not load against the current layout, so full synchronization regression
coverage was **not** available. The sync and engine files are unchanged.

**No in-game validation has been performed.** Previews are offline composites with
sample data and system fonts.

## In-game acceptance checklist

Restart the game client completely (new texture files are not picked up by
`/reload`).

- [ ] `/kt leaderboards` opens on World PvP with no Lua errors (BugSack).
- [ ] No texture shows as a green or white box.
- [ ] Minimum window: title plate, all five Warlords visible, nothing clipped.
- [ ] Enlarged window: banner replaces the title plate; art is not distorted.
- [ ] Rank 1 gold/crimson, 2-3 purple, 4-5 blue, 6+ steel.
- [ ] Names, "(you)", totals and STALE are readable over the dragon art.
- [ ] Rank order and totals match what the previous build showed.
- [ ] Each tab highlights alone; hover and press art look right.
- [ ] Battlegrounds and Lifetime show plain tables with no Warlord recognition.
- [ ] Search keeps true ranks; a nonsense search shows the empty message.
- [ ] Mouse wheel, scrollbar drag and page arrows work on all three boards.
- [ ] Window scale 75%, 100% and 135% and a UI-scale change look correct.
- [ ] Window drag, resize and close behave as before and persist after relog.
- [ ] "Refresh my stats" works; a 2.0.2 guildmate's scores still arrive.
- [ ] Guild Records page and the officer workspace behave as before.

## Rollback

1. Close the game.
2. Delete `Interface\AddOns\KeepersWarCommand`.
3. Unzip `KWC-2.0.2-pre-worldpvp-backup.zip` into `Interface\AddOns`.

SavedVariables do not need to change. In git, the pre-change checkpoint is commit
`b16cf2b` on `private/worldpvp-leaderboard`.
