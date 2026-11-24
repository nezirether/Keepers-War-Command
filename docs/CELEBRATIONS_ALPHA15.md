# War Celebrations and Historical Records • alpha.15

## Implemented

- Shared presentation policy wraps the existing Toast channels. The automatic queue has 12 entries, prioritizes significant moments and discards items after ten seconds or a guild/instance transition. Standard, Heroic and Legendary frame treatments use the current theme and existing art. Fade animation can be disabled independently or by reduced motion.
- Alerts has Off, Quiet, Balanced and Epic intensity, independent PvP, streak, bounty, milestone, CTA and guild-achievement toggles, the existing master sound switch and manual visual/sound previews. Quiet mutes automatic sound. Guild-wide chat announcements remain disabled. Preview does not create Chronicle entries or network traffic.
- Personal commendations count newly observed local PARTY_KILL evidence. The streak default is confirmed local killing blows, with thresholds 3, 5, 10, 15 and 20. Death, loading, world transitions and logout end the observed streak. Reload cannot reconstruct a past streak. The local observed count and personal best persist independently of native lifetime stats.
- The bounded Chronicle is under Alerts and retains up to 100 significant events per character per guild. It records title, evidence, timestamp and zone where known. Successful native ENCOUNTER_END events can enter the history when guild achievements are enabled. Automatic instance popups remain suppressed.
- A transition from active to completed in the authoritative bounty list can create a heroic completion moment. Claims alone and cancellation do not count as completion. Existing claims can have multiple claimants, so completion does not award an invented personal claimant.
- Authorized CTA managers have Victory, Objective completed and Withdraw actions in addition to Resolve and Stand down. Explicit outcomes are stored separately from the old board payload. Resolve alone remains unresolved as to success. Results are visible in the CTA detail pane. Remote guild celebration is opt-in through Guild achievements.
- Lifetime, Battlegrounds, Non-BG and Guild Records are the four historical Records tabs. Lifetime opens first. The removed installation-based tab has no replacement counter. Event logs, map-pin and copy-coordinate actions remain in the detail drawer. The verified 166-total/51-BG fixture produces 115 Non-BG. Missing or inconsistent inputs remain unavailable.
- Native honor reads occur at login and world entry, with coalesced retries at 1, 3 and 10 seconds. Criteria updates refresh both lifetime and supported area snapshots, in addition to existing HK/honor updates and guild-readiness triggers. The existing send signatures and ten-minute broadcast interval avoid repeated unchanged announcements.

## Event identity and compatibility

EVENT1 is an additive KWC3 message carrying kind, sender GUID, boot identifier, sequence, timestamp and original payload. The sender still transmits the original WORLDKILL, WORLDKB or WORLDDEATH packet for older clients. An updated receiver validates the GUID against the current roster, rejects envelopes over 30 seconds old, deduplicates the explicit ID, and bridges it with a matching legacy packet. Legacy reports wait half a second for the envelope. Two modern IDs remain distinct even when victim, zone and count match.

CTARESULT is an additive KWC3 message with CTA ID, explicit outcome, revision and timestamp. Only the poster or an officer on the current roster may supply it. A result requires the matching resolved board revision. A bounded 32-item, thirty-second wait handles board/result ordering. Stale, replayed and unauthorized results cannot inflate achievements. Older clients ignore these new message kinds and retain their original alerts and CTA status behavior. The established sync engine is reused unchanged.

Full verified names use the local roster GUID or exact current membership. Unknown first names stay unresolved. Verified historical aliases are resolved before PvP roster filtering. The Filibuster Fent/Fente fixture exercises the existing verified rename migration. Actual historical accounts still require matching GUID or an authorized alias link.

## Explicitly deferred for lack of authoritative evidence

- Personal completed-bounty counts at 1/5/20 require an authoritative assignment of the confirmed claimant. The current completion state and multiple claim submissions do not establish which claimant earned completion.
- Personal CTA participation counts at 1/5/20 require confirmed attendance. The existing Coming/Maybe/Busy responses represent intention. They cannot establish participation.
- Cumulative historical guild achievements require a deduplicated authoritative data source. This build records observed native encounters and authorized operation outcomes without inventing past guild totals.
- Legacy clients' exact retransmissions cannot be distinguished from a real repeated event with identical fields. They retain their existing repeat filters. Updated clients use explicit EVENT1 identities. No guarantee of perfect event identity is made for old packets without source IDs.
- Sound IDs 888 and 8959 reuse existing public KWC choices. Lua tests exercise calls. Their timbre and playback on Forever need live verification. No new sound asset library was supplied.

## Verification

The full public regression suite passed 371 checks on each of Lua 5.1 and LuaJIT. The celebration suite covers bounded queue, duplicate envelopes and legacy bridges, rapid distinct event IDs, full names, streak reset, completed/cancelled bounties, authorized CTA outcome, replay rejection, generic resolve, withdrawal, every curated skin, reduced motion and login/reload honor reads. The historical tests cover pre-install total 166, map-only BG summation, unavailable source values, native updates, guild exchange, reload and verified renames. These are simulated results. Actual Forever rendering, sound, timing and multi-player packet ordering remain pending.

## Focused live acceptance

1. Install the public alpha.15 folder after retaining the current build. Login and reload without killing anything. Compare lifetime honor and supported area figures with the native Statistics pane.
2. On Nez Dankdabs, get two quick honorable kills. Have a guildmate count popups. Verify full names and independent kill events. Enable All killing blows and test an own no-honor killing blow.
3. Enable streaks and reach three confirmed own killing blows, then die and repeat. Inspect the Chronicle, observed count and best streak. Reload and check the active streak has ended.
4. Preview all three levels, sound, Quiet, Off and reduced motion. Repeat under Trogdor, Horde, Alliance and Blood Moon.
5. Complete a bounty through the existing authorized lifecycle. A claim alone must produce no completion celebration. Replay the same completion to a peer.
6. Create a CTA and exercise Resolve, Withdraw, Cancel, Objective completed and Victory on separate operations. Turn Guild achievements on for a receiving guildmate. Verify authorization, result ordering and replay handling.
7. Open Records with historical statistics already present. Confirm four tabs, native Lifetime total, BG total, Non-BG difference, unavailable states, long-name tooltip and death coordinate actions.
8. Enter a dungeon, raid or battleground. Automatic celebrations must disappear and queued items must expire. Manual previews remain available. Leave and check that stale moments do not replay.
