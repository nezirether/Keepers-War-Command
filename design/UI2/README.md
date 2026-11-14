# Keepers War Command UI 2.0 design review

Open [the concept board](index.html) in a browser. The sidebar opens eight full-window concepts. [Design tokens and controls](index.html#components) show the palette, typography, tables, and button states. All records, counts, settings, and statuses shown are examples. Navigation and the alert preview links demonstrate the proposed paths. These are browser mockups for design review.

| Concept | Full-window preview | Proposed change |
| --- | --- | --- |
| Command Center | [PNG](screens/home.png) | Group activity already available to KWC above the existing feature shortcuts. |
| Settings Center | [PNG](screens/settings.png) | Make search and categories easy to reach. Results identify the existing destination and settings scope where known. |
| Alert Command Center | [Guild Death](screens/alerts.png) · [Bounty Spotted](screens/alerts-bounty.png) | Show alert states and actions on cards with configuration alongside. Use the existing popup art, move and lock controls, and local test functions. |
| War Room | [PNG](screens/war.png) | Give priority, commander, location, and response totals distinct places on each operation card. |
| Bounty Board | [PNG](screens/bounty.png) | Keep actions in a spaced toolbar, show the selected target, and explain when capture needs a valid target. |
| Guild LFG | [PNG](screens/lfg.png) | Keep all three tabs prominent and show filters, selected listing details, and available actions. |
| Guild Services | [PNG](screens/services.png) | Put sharing status, filters, and searchable results within easy reach. |
| Raid Operations | [PNG](screens/raid.png) | Group existing raid tools by task and explain why the Battle Resurrection preview can be unavailable. |
| Design system | [PNG](screens/components.png) | Share a palette and type scale with examples of navigation, buttons, toggle states, inputs, and tables. |

## Alert review decisions

- Guild Death and Bounty Spotted have separate popup and sound settings. The concept illustrates the existing move, lock, and reset actions. Dragging and persistence would remain in the existing positioning mechanism.
- Chat alerts, reminders, Guild LFG notices, and raid-only controls link to existing configuration. The concept omits move and test buttons where the current feature has no safe equivalent.
- Existing alerts expose fixed sounds with on/off controls. Sound selection and per-alert volume are outside this design. The approval mockups use the real alert textures and the existing Trogdor launcher mark.
- Live confirmation after implementation should cover readable labels at normal and smaller UI scales, local-only test output, drag persistence, and the module and raid availability states.

## Visual direction reference

The built-in image generation tool created the [visual direction board](visual-direction.png) from the supplied Keepers of Trogdor logo as a visual reference. It explores graphite, steel, bronze, crimson selection, restrained branding, and native-style spacing. It contains example component states for visual inspiration. Use the authored concept screens and the implementation plan for supported options and exact labels.

The generated board prompt described a landscape desktop game window with a small existing dragon motif, an Alert Command Center showing Guild Death and Bounty Spotted cards, a Position pane, and a column of component examples. It asked for clean alignment, readable labels, minimal ornament, and a dark in-game application style.

The owner approved the concepts on November 13, 2026. The browser mockups remain the design reference.
