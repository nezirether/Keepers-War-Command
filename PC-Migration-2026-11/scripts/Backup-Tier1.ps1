#Requires -Version 7
<#
.SYNOPSIS
  Tier 1 (irreplaceable AI-dev) backup for the 2026-11-21 Windows reinstall. COPY-ONLY.

.DESCRIPTION
  * Default is a DRY RUN (robocopy /L): nothing is written except a log in %TEMP%.
  * -Execute performs the copy into -Dest. Sources are only ever READ.
  * Never uses /MIR, /PURGE, /MOV or /MOVE. Never deletes anything.
  * Credentials/token stores are excluded by name (see $SecretExcludes).
  * Files are stored under <Dest>\Files\<DriveLetter>\<original path> so restore paths are unambiguous.
  * Also writes git bundles (--all refs, incl. stash) + per-repo git-state reports, then a SHA-256 manifest
    that compares every destination file against its source.

.EXAMPLE
  pwsh -File Backup-Tier1.ps1 -Dest E:\PCBK-2026-11              # dry run, prints sizes
  pwsh -File Backup-Tier1.ps1 -Dest E:\PCBK-2026-11 -Execute     # real copy (after approval)
#>
param(
  [Parameter(Mandatory)][string]$Dest,
  [switch]$Execute,
  [switch]$AllowLiveAppData,   # copy Codex SQLite even if Codex is running (NOT recommended)
  [switch]$SkipBundles,
  [switch]$SkipManifest
)
$ErrorActionPreference = 'Stop'
$U = $env:USERPROFILE
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDir = if ($Execute) { Join-Path $Dest 'Logs' } else { Join-Path $env:TEMP "PCBK-dryrun-$stamp" }
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir "robocopy-$stamp.log"

# ---- never copy these (auth tokens, cookies, browser-profile secrets) ----
$SecretExcludes = @('.credentials.json','auth.json','*.key','Cookies','Cookies-journal','Login Data*','Local State',
                    'Trust Tokens*','hosts.yml','cap_sid','*.lock','mcp-needs-auth-cache.json')
$SecretDirExcludes = @('.sandbox-secrets','Local Storage','IndexedDB','Session Storage','WebStorage','Network')

# ---- job list: Src, optional file filter, extra dir/file excludes, Live flag ----
$jobs = @(
  # Projects (D:)
  @{Src='D:\KeepersWarCommand'},
  @{Src='D:\KeepersWarCommand-ui2'},
  @{Src='D:\KeepersWarCommand-kwc2-codex-20261118'},
  @{Src='D:\KeepersWarCommand-dev56-recovery'},
  @{Src='D:\keepers old'},
  @{Src='D:\WarCommand'},
  @{Src='D:\TrogdorWarKommand'},
  @{Src='D:\KWC-Rebirth'},
  @{Src='D:\KWC-Hub'},
  @{Src='D:\KWC Addon Research'},
  @{Src='D:\MacroForgeAI'},
  @{Src='D:\MacroForgeAI-stress-1000'},
  @{Src='D:\WoW-Addon-Intelligence-Engine'},
  @{Src='D:\AI-Orchestrator'},
  @{Src='D:\'; Files=@('*.md','krt.txt'); Lev=1},
  # Projects (C:)
  @{Src='C:\Projects'},
  @{Src='C:\GuildRadioFM'},
  @{Src="$U\Desktop\KeepersWarCommand"},
  @{Src="$U\Desktop\KeepersWarCommand2.0"},
  @{Src="$U\Desktop\KWC_Claude_Code_Terminal_Setup"},
  # Ollie task state
  @{Src="$U\AppData\Local\AI-Orchestrator"},
  # WoW SavedVariables + in-game copies of own addons
  @{Src='D:\World of Warcraft\_forever_\WTF'},
  @{Src="$U\Desktop\WTF"},
  @{Src='D:\World of Warcraft\_forever_\Interface\AddOns\KeepersWarCommand'},
  @{Src='D:\World of Warcraft\_forever_\Interface\AddOns\WarCommand'},
  @{Src='D:\World of Warcraft\_forever_\Interface\AddOns\GuildRadioFM'},
  # Claude Code CLI (memories, project histories, skills, plugins list) - secrets excluded
  @{Src="$U\.claude"; XD=@('cache','shell-snapshots','session-env')},
  @{Src=$U; Files=@('.claude.json','.gitconfig'); Lev=1},
  # Claude Desktop: sessions + non-secret settings only (config.json holds oauth:tokenCache -> excluded)
  @{Src="$U\AppData\Local\Claude-Data\claude_pzs8sxrjxfjjc"; Files=@('claude_desktop_config.json','ccd-*.json','git-worktrees.json','mcp-user-tool-toggles.json','cowork-*.json'); Lev=1},
  @{Src="$U\AppData\Local\Claude-Data\claude_pzs8sxrjxfjjc\claude-code-sessions"},
  @{Src="$U\AppData\Local\Claude-Data\claude_pzs8sxrjxfjjc\local-agent-mode-sessions"},
  @{Src="$U\AppData\Local\Claude"},   # logs only
  # Codex: config, history, sessions, memories, skills, rules, DBs. NOT auth.json, packages, sandbox, plugins cache
  @{Src="$U\.codex"; Files=@('config.toml','history.jsonl','session_index.jsonl','version.json','installation_id','.codex-global-state.json'); Lev=1},
  @{Src="$U\.codex"; Files=@('*.sqlite','*.sqlite-wal','*.sqlite-shm'); Lev=1; Live=$true},
  @{Src="$U\.codex\sessions"},
  @{Src="$U\.codex\memories"},
  @{Src="$U\.codex\skills"},
  @{Src="$U\.codex\rules"},
  @{Src="$U\.codex\attachments"},
  @{Src="$U\.codex\generated_images"},
  # Editors / git tooling settings
  @{Src="$U\AppData\Roaming\Code\User"; XD=@('workspaceStorage','globalStorage')},
  @{Src="$U\.copilot"; Files=@('config.json'); Lev=1}
)

function Get-DestFor([string]$src) {
  $full = [IO.Path]::GetFullPath($src).TrimEnd('\')
  $drive = $full.Substring(0,1)
  $rest = $full.Substring(2).TrimStart('\')
  $base = Join-Path (Join-Path $Dest 'Files') $drive
  if ($rest) { Join-Path $base $rest } else { $base }
}

$codexRunning = [bool](Get-Process -Name codex,Codex -ErrorAction SilentlyContinue)
$results = @()
foreach ($j in $jobs) {
  if (-not (Test-Path -LiteralPath $j.Src)) { $results += [pscustomobject]@{Src=$j.Src; Status='MISSING'; Bytes=0; Files=0}; continue }
  if ($j.Live -and $codexRunning -and -not $AllowLiveAppData) {
    $results += [pscustomobject]@{Src="$($j.Src) [$($j.Files -join ',')]"; Status='SKIPPED-LIVE (close Codex, rerun)'; Bytes=0; Files=0}; continue
  }
  $dst = Get-DestFor $j.Src
  $rcArgs = @($j.Src, $dst)
  if ($j.Files) { $rcArgs += $j.Files }
  $rcArgs += '/E','/COPY:DT','/DCOPY:T','/R:1','/W:1','/XJ','/FFT','/NP','/BYTES','/NJH',"/UNILOG+:$log"
  if ($j.Lev) { $rcArgs += "/LEV:$($j.Lev)" }
  $rcArgs += '/XF'; $rcArgs += $SecretExcludes; if ($j.XF) { $rcArgs += $j.XF }
  $rcArgs += '/XD'; $rcArgs += $SecretDirExcludes; if ($j.XD) { $rcArgs += $j.XD }
  if (-not $Execute) { $rcArgs += '/L' }
  & robocopy @rcArgs | Out-Null
  $rc = $LASTEXITCODE
  # parse this job's summary from the tail of the log
  $tail = Get-Content $log -Tail 12
  $bytes = (($tail | Select-String '^\s*Bytes\s*:' | Select-Object -Last 1).Line -split '\s+' | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
  $files = (($tail | Select-String '^\s*Files\s*:' | Select-Object -Last 1).Line -split '\s+' | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
  $results += [pscustomobject]@{Src="$($j.Src)$(if($j.Files){' ['+($j.Files -join ',')+']'})"; Status=$(if($rc -lt 8){"OK($rc)"}else{"FAIL($rc)"}); Bytes=[int64]$bytes; Files=[int]$files}
}
$results | Format-Table -AutoSize | Out-String -Width 300 | Write-Host
$total = ($results | Measure-Object Bytes -Sum).Sum
Write-Host ("TOTAL files={0}  GB={1:N2}  mode={2}  log={3}" -f ($results | Measure-Object Files -Sum).Sum, ($total/1GB), $(if($Execute){'EXECUTE'}else{'DRY-RUN'}), $log)
$results | Export-Csv (Join-Path $logDir "jobs-$stamp.csv")
if (-not $Execute) { return }

# ---- git bundles + git-state reports (writes only into $Dest) ----
if (-not $SkipBundles) {
  $repos = @('D:\KeepersWarCommand','D:\WarCommand','D:\WoW-Addon-Intelligence-Engine','D:\KWC-Rebirth','D:\MacroForgeAI',
             'D:\AI-Orchestrator','D:\AI-Orchestrator\p\source','D:\AI-Orchestrator\worktrees\pipeline-verification-20261117\source',
             'C:\Projects\KeyStoneCouncil',"$U\OneDrive\Documents\GuildRadioFM","$U\OneDrive\Documents\ChatGPT\death counter",
             'D:\Users\jerry\JB Ventures\Shaggy Ink Farms\Website',
             "$U\Documents\Codex\2026-06-11\files-mentioned-by-the-user-guildradiofm\work\publish2",
             "$U\Documents\Codex\2026-06-11\shaggy-ink-farms-repo-in-github\work\repo",
             'E:\AI-DEV\Projects\KeepersWarCommand','E:\AI-DEV\Projects\KWC-WorkLaptop-1.8',
             'F:\2026-11-18\grf\work\GRFM','F:\2026-11-16\inspect-this-keepers-war-command-repository\work\guildradio-recovery')
  $bdir = Join-Path $Dest 'GitBundles'; New-Item -ItemType Directory -Force $bdir | Out-Null
  foreach ($r in $repos) {
    if (-not (Test-Path -LiteralPath $r)) { Write-Warning "bundle: missing $r"; continue }
    if ($r.Substring(0,1) -eq $Dest.Substring(0,1)) { Write-Host "bundle: $r lives on the destination drive; bundle it to the OTHER USB"; continue }
    $name = ($r -replace '[:\\ ]+','_').Trim('_')
    $g = @('-c','safe.directory=*','--no-optional-locks','-C',$r)
    git @g bundle create (Join-Path $bdir "$name.bundle") --all 2>&1 | Out-File -Append (Join-Path $logDir 'bundles.log')
    $v = git @g bundle verify (Join-Path $bdir "$name.bundle") 2>&1
    $state = @("# $r", "## branches", (git @g branch -avv), "## worktrees", (git @g worktree list --porcelain),
               "## stash", (git @g stash list), "## status", (git @g status --porcelain=v1 --untracked-files=all),
               "## commits not on any remote", (git @g log --branches --not --remotes --oneline --decorate),
               "## remotes", (git @g remote -v), "## bundle verify", $v)
    $state | Out-File (Join-Path $bdir "$name.git-state.txt") -Encoding utf8
  }
}

# ---- SHA-256 manifest: hash dest, re-hash source, compare ----
if (-not $SkipManifest) {
  $root = Join-Path $Dest 'Files'
  $rows = Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($root.Length + 1)
    $src = $rel.Substring(0,1) + ':\' + $rel.Substring(2)
    $dh = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    $sh = if (Test-Path -LiteralPath $src) { (Get-FileHash -LiteralPath $src -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash } else { 'SRC-MISSING' }
    [pscustomobject]@{ RelPath=$rel; Bytes=$_.Length; SHA256=$dh; SourceMatch=($dh -eq $sh) }
  }
  $rows | Export-Csv (Join-Path $Dest 'MANIFEST-SHA256.csv')
  $bad = @($rows | Where-Object { -not $_.SourceMatch })
  $sum = "files={0} bytes={1} mismatches={2} at {3}" -f $rows.Count, ($rows | Measure-Object Bytes -Sum).Sum, $bad.Count, (Get-Date -Format s)
  $sum | Out-File (Join-Path $Dest 'MANIFEST-SUMMARY.txt'); $bad | Export-Csv (Join-Path $Dest 'MANIFEST-MISMATCHES.csv')
  Write-Host $sum
  if ($bad.Count) { Write-Warning "Mismatches are expected only for files that changed after copy (live logs/sessions). Review MANIFEST-MISMATCHES.csv." }
}
