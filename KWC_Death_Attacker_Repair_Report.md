# Death attacker repair — private test report

## Findings
The prior implementation registered PLAYER_DEAD but did not read damage evidence. A half-second proximity scan overwrote a single candidate with nearby hostile units; it did not establish that they attacked the victim. The local display could substitute class/faction text for the actual suspect's name. Unknown legacy reports intentionally rendered "Attacker unidentified". The specific Righteous Bonez incident cannot be reconstructed without the victim's build, raw packet and death recap; this audit identifies code defects, not a verified cause for that individual incident.

## Repair
WorldPvPDeaths.lua now requests C_DeathRecap.GetRecapEvents after PLAYER_DEAD, with at most three attempts. It retains at most 32 recent damage entries, bounded to 15 seconds and the current life. Accessible source names, GUIDs, timestamps, damage and event types are retained. Class/faction enrichment requires an exact GUID match on a currently available unit. A lethal named hostile player damage entry renders "Killed by"; earlier player damage without a named lethal source renders "Suspected attacker". Pet/guardian lethal damage with no verified owner renders unknown. NPC, friendly and environmental lethal entries suppress automatic PvP claims. Missing/restricted recaps never fall back to proximity guesses. Manual reporting remains available.

Death generations cancel delayed work after resurrection; pending and reported state prevent duplicate automatic sends. Only one report is sent for a resolved death. Names and incoming text reject control characters, delimiter injection and WoW markup. Existing texture, placement, settings, Smart Mode and bounty button workflow remain intact; reports never create bounties automatically.

## API evidence and limitations
- Forever API documentation: https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/DeathRecapDocumentation.lua
- Blizzard recap display marks entry 1 as causedDeath: https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_DeathRecap/Mainline/Blizzard_DeathRecap.lua
- Independent addon author's actual Forever probe documents sourceFlags, sourceGUID and epoch timestamp fields: https://raw.githubusercontent.com/GudaAddons/HeadHunter/main/Detection/ForeverDeaths.lua
- Restricted combat-log APIs are not registered or called. UNIT_DIED and PARTY_KILL are not treated as independent attacker evidence. Continuous combat-log history and pet-owner discovery are unavailable through this implementation.
- Evidence is a bounded death-recap snapshot, not continuous damage capture.
- Field availability, flags, timestamp units and recap ordering on the user's installed build still require live confirmation. Errors/restricted values fail closed.
- Legacy WORLDDEATH uses sender as victim, a confidence-prefixed attacker string and sanitized zone. It has no extensible metadata or event ID. Class/faction/GUID evidence is retained locally, not sent in this legacy packet.
- Older reports still render. Older receivers may show the confidence prefix as part of a reported name and reject attacker fields longer than their old 48-character limit.
- The existing 12-second incoming repeat filter remains; it can suppress a legitimate rapid second death and cannot reject indefinitely delayed replay. Local automatic reporting resets on resurrection.
- No pet owner is guessed. No class/faction is invented. Unknown pet ownership is deliberately unidentified.
- Recaps unavailable after disconnect cannot be reconstructed. A reload starts fresh attribution; stale pre-session evidence is excluded.
- Guild reports remain member/victim assertions, not independently verified or cryptographically authenticated facts.
- Long name readability still requires visual testing; no artwork or layout redesign was made.

## Exact files changed
KeepersWarCommand/WorldPvPDeaths.lua
tests/alert_placement.lua

## Validation
All seven committed regression suites passed against files extracted from this exact commit. Lua 5.1 syntax passed for all 85 addon Lua files and committed Lua tests. The actual TOC initialization suite loaded 72 TOC paths, all nine Raid Tools modules, and seven tabs. Death tests exercise actual production handlers, confirmed/suspected/unknown attribution, multiple sources, DoT, pets/guardians, NPC/environment/friendly lethal damage, absent/restricted data, retries, duplicate events, resurrection, stale session evidence, BG exclusion, encoding, guild rendering, GUID metadata and bounded history. Existing drag/artwork/Smart Mode/recruitment/raid/leaderboard suites pass.

ZIP: one KeepersWarCommand folder, 88 runtime files, no tests/development documentation/Git data. CRC verification and byte-for-byte comparison to committed Git blobs passed. All nine unrelated synchronization working files were preserved byte-for-byte and excluded. The unfinished synchronization audit is NOT certified by this build; its prior failure remains separate work.

## Live acceptance checklist
Test direct player and DoT deaths; multiple attackers; nameless/hidden sources; pet and guardian kills; PvP followed by NPC/fall/environmental lethal damage; recap delay; resurrection and rapid repeat deaths; relog and disconnect; BG exclusion; guild recipients on current and older builds; optional class/faction enrichment; long names; sound/Smart Mode/drag/settings; manual fallback when recap is restricted. Confirm exactly one outbound report per qualifying death and no automatic bounty creation.

Live success is pending. No push, merge, publish or live installation was performed.

Commit: 6c7c292423d5afeaf1066049d7fa2bc9b56ad31f
ZIP: D:\KeepersWarCommand\KeepersWarCommand_DEV56_Death_Attacker_Fix_Private_TEST.zip
SHA-256: e16a78260e019ec39af21d90c57936de05153a2b2c5fb132f0050890d9a19931
