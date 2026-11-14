# UI 2.0 visual fidelity and feature parity review

## Comparison scope

Reviewed all eight approved screen concepts, both alert variants, the component sheet, the image-generated direction board, and the pre-correction Lua layout at a1fb7d7. The local Forever screenshots predate the reviewed build and do not show KWC open. The comparison below is between the approved reference and source-observable differences. Current and corrected in-game screenshots are pending.

| Area | Gap in the previous build | Correction and live check |
| --- | --- | --- |
| Main frame | Flat fills and a thin edge | Layered metal, inset bronze edge, corner plates and studs. Check trim contrast against several game backgrounds. |
| Header and branding | Small mark and identity | Taller brushed header, larger existing Trogdor texture, distinct brand and page title, steel Preferences and crimson Close. Verify title and hit areas at small scale. |
| Sidebar | Similar-looking rectangular rows | Grouped headings, muted idle rows, icons for supported destinations, and a crimson selected rail. Check scroll and icon visibility. |
| Typography | Weak separation from body copy | 24-unit page titles, 15-unit sections, 13-unit reading and navigation text; built-in Morpheus with Friz Quadrata fallback. Verify actual font metrics and wrapping. |
| Panels and borders | Flat shapes with little hierarchy | Shared opaque graphite steel texture, subtle grain, coordinated edge colors and spacing. Existing tables and feature layouts inherit the surface and control treatment. |
| Home | Plain shortcuts on disconnected rectangles | Title and subtitle, three existing summary metrics, and six full-card shortcuts with icons and descriptions. Check wrap at small scale and shorter screens. |
| Buttons and selected states | Limited difference among roles | Textured steel and crimson, hover border and lighting, pressed darkening, existing disabled alpha, and measured caption fallback. |
| Settings controls | Flat buttons and similar-weight sections | Shared button treatment, current On/Off values, and retained settings search and direct routes. |
| Alert Command Center | Artwork sample did not show placement | Distinct alert cards with right-hand settings, selected styling, local test actions, and a placement grid showing stored coordinates when available. Use Move Alert for real drag placement. Existing artwork, popup rules, and rules for sound and timing remain. |

WoW renders native frames and fonts. The reference uses browser typography and flexible CSS. Existing alert options use switches and bounded adjustments. Fixed sound on/off is supported. A sound picker and per-alert volume would require additional backend behavior. The static placement grid refreshes when the panel redraws. The existing popup is the live drag surface.

## Feature parity and backend audit

- Home actions still navigate to the same views. War Room, Calls to Arms, Bounty Board, PvP Leaderboard, Raid Operations, Recruitment, Guild LFG, Guild Services, Guild Roster, Addon Checker, Settings, and Sync Health retain their existing data and actions. Shared UI helpers update their visual treatment.
- Kept Raid Tools mounting, tabs, settings callbacks, alert previews, popup positioning, guild readiness, player identity, recruitment actions, bounty claims, and Call to Arms attendance. The main window still uses its existing drag and scale handlers. There is no new position storage.
- Retired both feature pages, the Commendations sidebar entry, the Achievements slash subcommand, milestone definitions, point calculations, award notices, operation wrappers, and standalone ACHPTS send and receive handlers. The sound preference helper now loads as AlertSounds.lua with the same settings keys and semantics.
- The legacy PVPCACHE points field remains in place. Outgoing records put the existing unavailable sentinel -1 in that field. The receiver still validates the legacy field for packet compatibility and does not apply points. Honor and area-stat synchronization use their existing authorization, ordering, and eligibility. Existing point values and achievement tables are neither cleared nor migrated. Existing PvP identity merges still carry historical points with the record.
- The corrected suites check legacy ACHPTS packets leave saved points intact and retain the stale-HK, authorization, and replay tests. Automated validation covers loading, callbacks, and selected states. It cannot verify texture appearance or clipping in Forever.

## Live comparison checklist

Capture Command Center, Alert Command Center with Guild Death and Bounty Spotted selected, and one representative view from every other sidebar section. Use the same UI scale and window size for before and after. Include a smaller-window run with sidebar scrolling. Compare texture detail, edge contrast, selected states, long labels, text alignment, and tooltips with the approved concept PNGs. In the alert center, test both previews, move and lock each alert, reload, then reset their positions. Verify mixed-client PvP reports, existing bounty claims, and Call to Arms attendance.
