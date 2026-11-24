# KWC Mastercraft III art handoff

Verified baseline: public alpha.11, Git 8389cf85b27b848cb17f71df354f5564ca9b81a5. Display sizes below are logical UI units, before client scaling.

| PNG filename | Master | TGA export | Current rendering |
| --- | --- | --- | --- |
| dashboard.png | 2048×1024 | dashboard.tga, 512×256 RGBA | Right half of the flexible Dashboard card plus 42, 108 high. Focal cover crop. Keep the subject to the right and the left quiet. Two buttons overlay the lower right. Also used in the right half of the 74-high gallery preview. |
| header.png | 2048×256 | header.tga, 512×64 RGBA | 86 high and window width minus 198, or 722–1502 wide. Full-image stretch. Fade the left to transparent under the title and status. Protect the close button in the upper right. |
| crest.png | 512×512 | crest.tga, 128×128 RGBA | 46×46 sidebar and 40×40 gallery. Center the silhouette with transparent margins. |
| thumbnail.png | 512×288 | thumbnail.tga, 256×128 RGB | 62×36 tile with cover crop. Intake first crops the master to 512×256 around the focal point before downsampling. Leave room on all edges. |
| alert.png | 1024×256 | alert.tga, 512×128 RGBA | Full-image stretch over 404×98. Subdue behind icon and text. Protect the upper-right close control. |
| ornament.png | 256×256 | ornament.tga, 64×64 RGBA | 19×19 corner of supported cards. Prefer a simple transparent shape. |
| material.png | Tileable 4:1, at least 256×64 | material.tga, 256×64 RGBA | Subtle surface in panels, right half of header and scene, gallery preview, and 198×52 sidebar footer. The strip stretches to the available area. |
| trim.png | Tileable 8:1, at least 256×32 | trim.tga, 256×32 RGBA | 18-high header strip and fitted dashboard, gallery, tab, and secondary button treatments. Leave the center quiet behind text. |

Focal coordinates are normalized from the top left. Use [0.5, 0.5] for centered subjects. Cover-cropped assets use both coordinates. Thumbnail intake adjusts the y coordinate after cropping, then the UI performs its own cover crop. Header, alert, material and trim preserve the full source bounds during display. Header and alert motifs can stretch, so avoid precision-dependent lettering and geometry. The requested dimensions are supported.

The War Room defaults to 1100×700 logical units. Bounds are 920×580 through 1700×1100, further constrained by the client viewport. The requested scale is clamped to 0.75–1.35 and can be reduced to fit. Geometry lives in KWCDB.settings.ui2Window, scale in ui2Scale. Theme selection, favorites and recent themes remain keyed by character GUID in KWCDB.settings.ui2Appearance. The account setting ui2Skin remains a migration fallback. Keep all approved IDs unchanged.

## Delivery layout

    art-inbox/
      incoming/<skin-id>/<delivery-id>/
        manifest.json
        source/<slot>.png
        masters/
        rights/
      staging/<skin-id>-<delivery-id>/
        KeepersWarCommand/Media/Art/<skin-id>/<slot>.tga
        KeepersWarCommand/UI/ThemeArt.lua
        docs/PHOENIX_ART.json
        STAGING_REPORT.json
      templates/ART_PACKAGE.schema.json
      templates/ART_PACKAGE.template.json
      tooling/

Deliver eight static sRGB PNGs named exactly as shown. Keep editable masters and prompt, creator, source and license records in masters/ and rights/. The manifest has one approved skin ID and a source, license and focal point per slot. Use original art or documented redistribution rights. Leave labels, watermarks, scores and UI controls out of the art. The game supplies those elements.

The converter assumes sRGB for untagged PNGs and converts embedded ICC profiles to sRGB. It produces uncompressed true-color TGA, 32-bit BGRA with 8-bit straight alpha for RGBA slots and 24-bit BGR for the flattened thumbnail. Dashboard alpha may be fully opaque. Header, crest, alert, ornament, material and trim require both transparent and visible pixels. The thumbnail must arrive opaque.

## Check, stage, review, register

Use Python 3.10 or newer with Pillow. From the inbox run:

    python tooling/art_intake.py incoming/<skin-id>/<delivery-id> --repo <public-checkout>
    python tooling/art_intake.py incoming/<skin-id>/<delivery-id> --repo <public-checkout> --stage staging/<skin-id>-<delivery-id>

Check mode exports and validates in memory. Stage creates a new candidate directory. It rejects overwrites, previously approved entries, files outside the pack, unknown IDs, invalid focal coordinates, bad master dimensions and unreadable or invalid runtime TGAs. Each incoming file is limited to 64 MiB. Tile widths must be at most 4096 px. An eight-slot pack has about 1.1 MiB of uncompressed texture pixels. The active skin and pooled gallery rows load textures on demand. Texture caching, perceived sharpness and scale remain in-client checks.

Before adoption, compare STAGING_REPORT.json's baseline manifest SHA-256 to the current checkout and rerun intake if it differs. Review source rights, seamless tiling, visual balance, contrast and control states in game. Check full Dashboard, Records, sidebar, Appearance Gallery and Alerts at the minimum and expanded sizes. Make sure all buttons remain readable and clickable. Verify the artwork again at a larger UI scale. The validator covers structure and format. Human approval covers aesthetics, licensing and legibility.

After art approval, copy only the staged TGA files, generated ThemeArt.lua and merged PHOENIX_ART.json to their corresponding public-checkout paths. Run python tools/theme_art.py and the public appearance tests. Commit those assets and registrations together. The public packager checks committed blobs before writing the ZIP. Keep all drafts, PNGs, masters, rights records and STAGING_REPORT.json outside the addon. No artwork is approved by this phase.

## Public registration and fallbacks

The public TOC loads ThemeArt.lua before PublicThemes.lua. ThemeCatalog.lua builds the same 100 themes. Approved art overlays visual roles by exact ID after those themes are assembled. PHOENIX_ART.json preserves the original flagship entries and supports a separate production map keyed by approved ID. With no approved package, the existing flagship or shared style continues to render. A missing approved asset blocks packaging. If the client reports a failed crest texture load, the renderer attempts Emblem.tga. Other decor leaves the underlying palette or solid surface visible. Thumbnail failures leave the gallery swatches. Theme art cannot change anchors, tabs, roster data or gameplay callbacks.

Source audit covers KeepersWarCommand/UI/WarRoom.lua, WarRoomSkin.lua, Toast.lua, PublicThemes.lua, ThemeCatalog.lua, Pages/Dashboard.lua and Pages/AppearanceGallery.lua. Existing assets are under Media/ and Media/Themes/. Approved studio assets use Media/Art/.

## Tests available

    python tools/test_art_intake.py
    python tools/test_theme_art.py
    python tools/theme_art.py

Run tests/appearance_gallery.lua in Lua 5.1 and LuaJIT from the public checkout before adopting each batch. It exercises all 100 gallery entries, public routes, state preservation and zero network sends. Run the visual checklist in Forever 1.60.1 before packaging reviewed art.

## Approved theme IDs in gallery order

- trogdor, trogdor-inferno, trogdor-warchief, trogdor-bronze, trogdor-obsidian, trogdor-bloodfire, trogdor-iron, trogdor-ashen, trogdor-royal, trogdor-legacy
- classic, horde, alliance, horde-alliance, orgrimmar, stormwind, undercity, thunder-bluff, ironforge, darnassus
- dalaran, the-barrens, felwood, ashenvale, stranglethorn, winterspring, silithus, blackrock-mountain, tanaris, eastern-plaguelands
- arcane, fel-magic, frostmourne, holy-light, shadow, necromancer, nature-guardian, elemental, dragonflight, runic
- blood-moon, blood-pact, vampire, dark-lord, abyss, crimson-reaper, gothic-cathedral, cursed-iron, dark-ritual, midnight
- sleek, sleek-dark, sleek-light, pure-black, pure-white, graphite, frosted-glass, minimal-bronze, monochrome, soft-gray
- jedi, sith, galactic-republic, dark-empire, cyberpunk, neon-city, starship, holographic, synthwave, void-tech
- zen, samurai, shogun, bamboo, jade-temple, cherry-blossom, koi-garden, mountain-mist, onyx-lotus, golden-dragon
- forest, ancient-oak, desert, ocean-depths, frozen-tundra, volcanic, thunderstorm, autumn, moonlit-grove, sunrise
- royal-gold, pirate, steampunk, viking, dwarven-forge, elven-silver, blood-steel, winter-festival, hall-of-champions, burninator
