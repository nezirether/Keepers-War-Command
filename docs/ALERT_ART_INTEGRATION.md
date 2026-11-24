# KWC Alert Art Pack v1 — integration notes

Branch `claude/alert-art-v1`. Baseline is the verified public **alpha.15** build: ZIP sha256 `f8adba47…b0de`, upstream `codex/phoenix-public` @ `899b316`. Art integration only. PvP tracking, statistics, event deduplication, guild sync, WarSpoils, KWCC and the 13-skin curated collection are untouched.

## What changed

| File | Change |
| --- | --- |
| `KeepersWarCommand/UI/AlertArt.lua` | **New.** Plate registry, event→plate resolver, layout, text-following scrim, arrival motion, artwork preview. |
| `KeepersWarCommand/Media/Alerts/*.tga` | **New.** 10 plates, 512×256 32-bit BGRA (painted area 512×171), plus `ScrimFade.tga` 64×8. 5.0 MiB total. |
| `KeepersWarCommand/UI/Toast.lua` | Keeps references to the card chrome (`f.chrome`, `f.themeArt`, `f.border`). One guarded hook `T.Decorate` runs in `Channel:Present` after text and actions are set (+7/−2 lines). |
| `KeepersWarCommand/UI/Celebrations.lua` | Default `eventArt=true` added to the celebration preferences (additive key). |
| `KeepersWarCommand/UI/Pages/Alerts.lua` | "Event artwork" switch and an "Artwork preview" button in Alert policy. |
| `KeepersWarCommand/KeepersWarCommand.toc` | `UI/AlertArt.lua` after `UI/Celebrations.lua`. |
| `tools/alert_art.py`, `tools/alert_art_preview.py`, `docs/ALERT_ART.json` | Converter + validator, offline contact sheet, asset manifest. |
| `tests/alert_art.lua` | New 93-check suite. Add `tests/alert_art.lua` to the suite list in your `tests/run_all.sh` (not in the patch, so it cannot clobber the newer upstream gate). |

## Event → artwork

| Alert | Plate |
| --- | --- |
| Enemy slain (honorable kill) | HonorableKill |
| Killing blow (own, no honor) | KillingBlow |
| Streak milestone / Legendary preview | KillStreak |
| Guildmate slain | Fallen (no glint; somber) |
| Bounty target spotted | BountySighting |
| Bounty completed (War Celebration) | BountyClaimed |
| New Call to Arms | CallToArms |
| CTA Victory / Objective (own or guild) / Heroic preview | CTAVictory |
| Personal milestone / Standard preview | Commendation |
| Bounty created | BountyPosted. alpha.15 has no bounty-created popup, so this plate appears only in Artwork preview, or when a future alert passes `content.art='bountyPosted'`. No new alert was added. |
| WarSpoils award | BountyClaimed is reserved. WarSpoils has no toast in alpha.15. A future caller passes `art='bountyClaimed'`. |
| Guild LFG | Classic card (not in the pack) |

Any caller can pass `content.art='<key>'` to choose a plate, or `art=false` to keep the classic card.

## Rendering rules

- The toast body keeps its size (404/460/540×98), anchors, text, icon, buttons, countdown, drag, Move/Lock, scale and position. The plate is a texture centred on the body, sized `max(width×1.12, 98/0.62×3)`. It extends past the body. `SetClampRectInsets` keeps the whole plate on screen.
- Artwork creates **no frames**, only textures. Mouse hit-testing is the unchanged toast body. The test suite enforces this.
- The theme-engine `base` colour fills a backing behind the live text. Its width follows the widest line, from at least 42% of the body to at most the body width minus 28. Long full names stay readable, and short alerts leave the hero art bright. The close control gets the same backing.
- Skins whose text colour is dark (luminance < 0.55) keep the classic card. On those skins the plates would force dark text onto dark art. Text colour always comes from the theme engine. No colours are overridden.
- Arrival motion is a 0.28 s 4.5% settle plus one additive glint: 0.16 Standard, 0.32 Heroic, 0.5 Legendary, none for Fallen. Both are off when *Animations* is off or *Reduced motion* is on. The existing fade and countdown are unchanged.
- Each channel loads only the plate for the alert it shows. With all six art-capable channels shown, at most ~3 MiB of plates are resident at once. Artwork failures (missing file, client refusal) fall back to the classic card through `Kit.Safe`.

## Verification

- `tests/alert_art.lua`: 93/93 on Lua 5.1 and LuaJIT. Mutation checks (wrong mapping, added mouse frame, ignored reduced motion, truncated title) each fail the suite.
- The existing suites ran from the KWC-2.0 laptop checkout, which is still alpha.2-era. The 371-check alpha.15 suite is not on this machine. Results matched the pre-change baseline line for line: 214 PASS / 10 FAIL. The 10 failures are pre-existing harness/version mismatches. `kwcc_security` and `ui_layout` need the KWCC folder, which was not modified.
- `luac5.1 -p` 126 files, global-write lint clean, TOC complete, `tools/alert_art.py --check` OK.
- **Not yet verified:** in-game Forever rendering, filtering/sharpness at UI scale, actual clamp behaviour, and timing feel. See the live checklist below.

## Apply onto the newest public branch

From the public checkout (`codex/phoenix-public` or newer), on a fresh branch:

    git switch -c claude/alert-art-v1 899b316        # or the current public tip
    git am --3way 0001-*.patch                         # binary patch: includes the TGAs
    python3 tools/alert_art.py --check
    ./tests/run_all.sh                                 # the full 371-check suite + alert_art
    python3 tools/package.py

Conflicts can only occur in the four small hunks in Toast.lua, Celebrations.lua, Alerts.lua and the TOC, if Codex has since edited those exact lines. Re-apply them by hand from the table above. Everything else is a new file. To regenerate the TGAs from the masters, run `python3 tools/alert_art.py --src art-inbox/KWC_Alert_Art_Pack_v1/KWC_Alert_Art_Pack_v1/assets --write`.

## Live checklist (Forever)

1. Alerts › Artwork preview: click ten times. Each plate appears, text is crisp, and the close ✕ is visible and clickable.
2. Standard/Heroic/Legendary previews under Balanced and Epic. Check the Legendary 540 width.
3. Guildmate slain preview: *Post bounty* and *Death log* work. Clicking the plate overflow above or below the body must not block the world.
4. Move: drag to every screen edge. The plate must stay fully on screen.
5. Reduced motion on, then Animations off: no settle or glint.
6. Switch through all 13 curated skins. Light skins show the classic card.
7. UI scale 0.64 and 1.0. Check plate sharpness. If plates look soft at 1440p+ / high scale, a 1024×512 export is a one-line manifest change (2 MiB per plate).
