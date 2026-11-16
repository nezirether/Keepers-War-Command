# KWC project state

## USB baseline and branch roles

The secondary checkout at `D:\AI-DEV\Projects\KeepersWarCommand` is based on `e5afb94` (KWC `1.7.0`, UI 2.0 private testing). GitHub is the shared exchange point, `main` is the integrated branch, and `work-laptop/development` is this laptop's only writable branch. The home PC's unpushed state is unknown. Its `dev/ui-2.0` and other branches may be active and newer than this baseline.

## Runtime and repository map

- The [manifest](../KeepersWarCommand/KeepersWarCommand.toc) declares Interface `16001` for WoW Forever 1.60.1 and defines Lua load order, SavedVariables, and optional dependencies. Required libraries are bundled. Overlord and War Effort Scout are optional.
- [KeepersWarCommand/](../KeepersWarCommand/) is the installable addon. `Core.lua` handles startup, events, and guild identity. `Network.lua` queues addon messages, `Sync.lua` handles guild sync, and `UI.lua` and `UITheme.lua` provide the main UI. Raid Tools are embedded under `Modules/RaidTools/`.
- [tests/](../tests/) contains 20 standalone Lua scripts at this baseline. [development/](../development/) contains implementation and verification notes. [design/UI2/](../design/UI2/) contains the reference art and static design board.

## Compatibility and validation limits

Keep Lua 5.1 compatibility. [ForeverCompat.lua](../KeepersWarCommand/Modules/RaidTools/ForeverCompat.lua) requires addon-local helpers because earlier writes to Blizzard's global `C_Spell` tainted protected UI. Shared guild features require guild membership, verified guild identity, and compatible clients.

The [installation guide](../INSTALLATION.md) and [CurseForge upload notes](../CURSEFORGE_UPLOAD_INFO.md) still reference `1.6.0-alpha.1`. Use the manifest at the selected commit and that revision's package evidence for version and artifact details. Lua tests simulate client behavior. Native layout, scale, clipping, combat behavior, persistence across reloads, and multiplayer sync require checks in Forever. See the [UI 2.0 verification notes](../development/UI2_Implementation_Plan.md).
