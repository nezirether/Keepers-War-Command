# READ-ONLY git inventory. No fetch, no writes (uses --no-optional-locks).
param([string]$ListFile, [string]$OutCsv)
$rows = foreach ($g in Get-Content $ListFile) {
  $wt = Split-Path $g -Parent
  $isWorktree = -not (Get-Item -LiteralPath $g -Force).PSIsContainer
  function G { git -c safe.directory=* --no-optional-locks -C $wt @args 2>$null }
  $common = (G rev-parse --path-format=absolute --git-common-dir)
  $branch = (G rev-parse --abbrev-ref HEAD)
  $head   = (G rev-parse --short HEAD)
  $remote = ((G remote -v) | Select-Object -First 1) -replace '\s+\(fetch\)',''
  $status = @(G status --porcelain=v1 --untracked-files=all)
  $tracked = @($status | Where-Object { $_ -notmatch '^\?\?' }).Count
  $untracked = @($status | Where-Object { $_ -match '^\?\?' }).Count
  $unpushed = @(G log --branches --not --remotes --oneline).Count
  $branches = @(G for-each-ref --format='%(refname:short)' refs/heads).Count
  $stashes = @(G stash list).Count
  $wts = @(G worktree list).Count
  $sub = if (Test-Path -LiteralPath (Join-Path $wt '.gitmodules')) { 'yes' } else { '' }
  $last = (G log -1 --format='%cs %s')
  [pscustomobject]@{ Path=$wt; Worktree=$isWorktree; CommonDir=$common; Branch=$branch; Head=$head; Remote=$remote;
    DirtyTracked=$tracked; Untracked=$untracked; UnpushedCommits=$unpushed; LocalBranches=$branches; Stashes=$stashes;
    Worktrees=$wts; Submodules=$sub; LastCommit=$last }
}
$rows | Export-Csv -Path $OutCsv
$rows
