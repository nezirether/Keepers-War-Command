# Claude alert artwork merge • alpha.16

## Source and provenance

The clean public checkout at work/KWC-2.0-public was on codex/phoenix-public at 899b316f8bd605e5b6d391d75ac3c4a4a990e4a5. That is the alpha.15 build with native honor retries, event envelopes, historical Records and War Celebrations. The D-drive project directory has no Git metadata. The working public Git checkout is the development source used for this integration.

Claude's artifact directory is D:/AI-DEV/Projects/KWC-2.0/dist/2.0.0-alpha.15-alertart.1. The patch's source commit is 28e7d65a3a5874105ea6953f9974dd2b9138dd2e. The supplied documentation, JSON manifest, ten-plate contact sheet, 93-check artwork results and baseline/after regression logs were reviewed. The older 214-pass/10-fail logs were evidence of Claude's environment only. The patch applied cleanly after comparison against the current alpha.15 source.

The merge adds the supplied artwork module, ten TGA plates, shared scrim, saved artwork preference, preview, manifest and tools. Existing alpha.15 gameplay detectors, deduplication, honor refresh and outcome protocols remain the implementation used by the build. The patch was imported into the current public branch. No packaged source tree was copied over it.

## Layout repair

Toast.LayoutContent measures the current text at the actual popup width. The kicker, full title, detail, location and action rows have independent anchors. The frame grows to fit wrapped names and action rows. The reserved close-button area remains clear. Location text sits above the buttons in both artwork and classic mode. Four action controls fit in two rows. For a retained local death record with coordinates, Drop Pin and Copy Coordinates use that record. Post bounty and Death log retain their existing callbacks. A guildmate report with only a zone does not invent map coordinates.

The plate uses textures behind the existing input frame. Tests assert no additional mouse-capable art frames. Plate sizing and clamp insets respond to the content-fitted body. Actual clipping and screen-edge clamping at high scale remain client checks.

The supplied contact sheet was regenerated with Windows font fallbacks, full-name examples and separated location/action rows. It is an approximate offline render. Lua layout tests inspect actual public frame anchors at widths 404, 460 and 540 and scales 0.64, 1 and 1.35. Those checks do not simulate actual pixel rasterization or physical mouse hit testing.

## Event assignments

Honorable kill, killing blow, streak, slain, bounty sighting, bounty completion, CTA, CTA victory and commendation use the supplied resolver. BountyPosted remains available for preview and future callers. WarSpoils may use the reserved BountyClaimed illustration in the future. This merge adds no automatic bounty-created or WarSpoils-award event source.

Light skins keep the classic card to preserve theme text contrast. The saved Event artwork toggle and Artwork preview work through Alerts. Plate arrival motion and glint follow Animations and Reduced motion. Existing automatic instance suppression, manual preview and source-event deduplication tests are part of the complete public suite.

## Automated evidence

- All 479 public assertions passed in Lua 5.1 and LuaJIT. This includes Claude's unchanged 93 artwork assertions, the 14 layout checks, 27 existing alert checks, verified surname/rename tests, native Records, guild-scoped synchronization, SavedVariables and celebration tests.
- Syntax compilation passed for 134 public/test Lua files in both runtimes.
- tools/alert_art.py --check verified the ten 512×256 RGBA plates and 64×8 scrim against the manifest. The existing theme asset gate also passed.
- The public packager validates both artwork registries against committed source bytes before packaging. TOC files, Interface 16001, CRC, public-only archive root and byte-for-byte commit provenance are checked by the packager.
- tests/run_all.sh now accepts --public-only and includes the current public suites and both new artwork/layout suites.

## Live acceptance still required

1. Under the normal Forever UI scale, preview all ten plates and each celebration level. Verify full names, sharpness and readable theme backing.
2. Preview Guildmate Slain with two actions. On an actual local death, inspect the zone and coordinates, click Drop Pin and Copy Coordinates, and check their results. Repeat with a long victim and attacker name.
3. Repeat at low and high alert scales, move each popup to the screen edges, and verify all artwork remains visible. Click outside the popup body to check that overflow art lets world input through.
4. Toggle artwork, reduced motion and animations during separate previews. Switch through all 13 current skins, especially Pure White and Cherry Blossom.
5. Verify one event produces one automatic popup through updated peers and the legacy bridge. Reload and compare native honor without another kill. Enter a prohibited instance and verify automatic popups disappear while manual previews still work.

The build is a public-only private test candidate. Forever rendering, actual click behavior, texture filtering and motion feel have not been signed off in game.
