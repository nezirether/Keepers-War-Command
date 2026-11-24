# CurseForge upload candidate • 2026-11-24

- Existing project https://www.curseforge.com/wow/addons/keepers-war-command
- Project ID 1801567
- Display name Keepers War Command 2.0.0-alpha.16
- File KeepersWarCommand-2.0.0-alpha.16.zip
- Game World of Warcraft
- Flavor Forever
- Version 1.60.1, Interface 16001
- Release type Alpha
- Use manual release after approval
- File changelog CURSEFORGE_CHANGELOG.md
- Project description CURSEFORGE_DESCRIPTION.md

The project currently distributes 1.8.2 for Forever. The alpha.16 candidate is prepared for the same client. This preparation does not upload or replace the current public file.

## Checks before public release

Automated checks run against this public source commit and the extracted candidate. Native Forever rendering, mouse behavior at screen edges, sound, high UI scales and live two-client packet ordering remain pending. Verify these using docs/ALERT_ART_MERGE_ALPHA16.md before approving the upload for public availability.

Art provenance is recorded in docs/ALERT_ART.json and docs/PHOENIX_ART.json. The existing project license is All Rights Reserved. Bundled components keep their own licenses and notices.

An API upload requires an author token. The upload payload in curseforge-metadata.json selects Alpha and manual release and specifies 1.60.1. Check Forever in the author dashboard when uploading.

The final package hash and source commit are written to the accompanying release manifest after packaging.
