# Installing Keepers War Command

Requires World of Warcraft: Forever 1.60.1 (Interface 16001). Shared guild features require guild membership, a verified guild identity and compatible KWC clients. The package includes its required addon libraries. Overlord and War Effort Scout are optional.

Download the official stable `KeepersWarCommand-2.0.0.zip` from [CurseForge](https://www.curseforge.com/wow/addons/keepers-war-command/files/9793652) or the matching [GitHub release](https://github.com/nezirether/Keepers-War-Command/releases/tag/v2.0.0).

1. Exit the game. If updating, back up the existing KeepersWarCommand addon folder and your WoW SavedVariables files.
2. Replace the old addon folder with the KeepersWarCommand folder in the ZIP. The final path is Interface/AddOns/KeepersWarCommand/KeepersWarCommand.toc. Keep your existing SavedVariables.
3. Launch Forever and enable the addon in the AddOns list. Type /kt.
4. Open Addon Checker to verify the installed version. The stable 2.0.0 ZIP displays the embedded version `2.0.0-alpha.16` in Addon Checker.

To roll back, exit the game, save a copy of the current data, and restore the previous addon folder with its matching SavedVariables backup. Updates and rollbacks can change which guild records are visible. Keep both backups if you need to recover newer records.

Report issues at https://github.com/nezirether/Keepers-War-Command/issues. Include the addon version, Forever client version, steps and Lua error text. For guild issues include the /kwc guilddebug output, which clients were online, and relevant Sync Health outcomes. Leave private chat, officer notes and SavedVariables out of public reports.
