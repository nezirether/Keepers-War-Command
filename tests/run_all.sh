#!/usr/bin/env bash
# KWC 2.0 private-build gate. Run from the repository root.
# Requires lua5.1, luac5.1 and luajit on PATH.
set -u
fail=0
public_only=0
[ "${1:-}" = "--public-only" ] && public_only=1
addons="KeepersWarCommand"
suites="tests/kwc_load.lua tests/identity_rename.lua tests/board_sync.lua tests/alerts.lua tests/killing_blows.lua tests/ui_layout.lua tests/public_features.lua tests/warspoils.lua tests/phoenix_integration.lua tests/historical_deaths.lua tests/appearance_gallery.lua tests/name_echo.lua tests/celebrations.lua tests/alert_art.lua tests/alert_layout.lua"
if [ $public_only -eq 0 ]; then
 addons="$addons KeepersWarCommand_Command"
 suites="$suites tests/kwcc_security.lua"
fi
echo "== Lua 5.1 syntax (luac5.1 -p) =="
n=0;bad=0
while IFS= read -r f; do n=$((n+1)); luac5.1 -p "$f" || { echo "SYNTAX FAIL $f"; bad=$((bad+1)); }; done < <(find $addons tests -name '*.lua' -not -path 'tests/legacy/*')
echo "syntax: $n files, $bad errors"; [ $bad -eq 0 ] || fail=1
echo "== TOC manifests =="
for addon in $addons; do
  toc="$addon/$addon.toc"; miss=0; cnt=0
  grep -q '^## Interface: 16001' "$toc" || { echo "FAIL $toc Interface"; fail=1; }
  while IFS= read -r line; do
    line="${line%$'\r'}"; [[ -z "${line// }" || "$line" == \#* ]] && continue
    cnt=$((cnt+1)); [ -f "$addon/${line//\\//}" ] || { echo "MISSING $addon/$line"; miss=$((miss+1)); }
  done < "$toc"
  echo "$toc: $cnt files, $miss missing"; [ $miss -eq 0 ] || fail=1
done
if [ $public_only -eq 0 ]; then
grep -q '^## Dependencies: KeepersWarCommand$' KeepersWarCommand_Command/KeepersWarCommand_Command.toc && echo "KWCC requires KWC: yes" || { echo "FAIL KWCC dependency"; fail=1; }
fi
echo "== Global-write lint (own files) =="
g=$(for f in $(find KeepersWarCommand/UI KeepersWarCommand/Engine -maxdepth 1 -name '*.lua'; find KeepersWarCommand/UI/Pages ${addons#KeepersWarCommand} -name '*.lua'); do luac5.1 -l -p "$f" | grep SETGLOBAL | grep -v -E '; (KWC|KWCDB|KWCC|KWCCDB|SLASH_KEEPERSWARCOMMAND[0-9]|KeepersRaidTools[A-Za-z]*|KRTForeverNotesDB)$' | sed "s#^#$f #"; done)
[ -z "$g" ] && echo "no unexpected global writes" || { echo "$g"; fail=1; }
echo "== Suites (LuaJIT and Lua 5.1) =="
for t in $suites; do
  for vm in luajit lua5.1; do
    args=()
    if [ $public_only -eq 1 ] && [ "$t" = tests/board_sync.lua ]; then args+=(--public-only); fi
    out=$($vm "$t" "${args[@]}" 2>&1); rc=$?
    echo "$(echo "$out" | tail -1)  [$vm]"
    [ $rc -eq 0 ] || { echo "$out" | grep -v '^PASS' | head -5; fail=1; }
  done
done
[ $fail -eq 0 ] && echo "GATE: PASS" || echo "GATE: FAIL"
exit $fail
