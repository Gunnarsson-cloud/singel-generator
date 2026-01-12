[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$Repo,

  [Parameter(Mandatory=$true)]
  [Int64]$RunId,

  [int]$PollSeconds = 8,

  [int]$TimeoutMinutes = 30,

  [switch]$ShowFailedLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI (gh) not found. Install it and run 'gh auth login'."
}

$runUrl = "https://github.com/$Repo/actions/runs/$RunId"
Write-Host "Watching GitHub Actions run $RunId in $Repo ..." -ForegroundColor Cyan
Write-Host "Run URL: $runUrl" -ForegroundColor DarkGray

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)

function Get-Run([Int64]$Id) {
  # NOTE: 'htmlUrl' is NOT a valid field anymore. Use 'url' or build link ourselves.
  $raw = gh run view $Id --repo $Repo --json status,conclusion,createdAt,updatedAt,displayTitle,name,event,headBranch,headSha,url 2>$null
  if (-not $raw) { return $null }
  return ($raw | ConvertFrom-Json)
}

while ($true) {
  if ((Get-Date) -gt $deadline) {
    throw "Timeout after $TimeoutMinutes minutes waiting for run $RunId. Open: $runUrl"
  }

  $run = Get-Run -Id $RunId
  if (-not $run) {
    Write-Host ("[{0}] (no data yet) retrying..." -f (Get-Date -Format "HH:mm:ss")) -ForegroundColor Yellow
    Start-Sleep -Seconds $PollSeconds
    continue
  }

  $status = "$($run.status)".ToLowerInvariant()
  $concl  = "$($run.conclusion)".ToLowerInvariant()

  if ($status -eq "completed") {
    if ($concl -eq "success") {
      Write-Host ("[{0}] ✅ completed: success - {1}" -f (Get-Date -Format "HH:mm:ss"), $run.displayTitle) -ForegroundColor Green
      Write-Host "Run URL: $runUrl" -ForegroundColor DarkGray
      break
    } else {
      Write-Host ("[{0}] ❌ completed: {1} - {2}" -f (Get-Date -Format "HH:mm:ss"), $concl, $run.displayTitle) -ForegroundColor Red
      Write-Host "Run URL: $runUrl" -ForegroundColor DarkGray

      Write-Host "`n--- Failed logs ---" -ForegroundColor Yellow
      gh run view $RunId --repo $Repo --log-failed | Out-Host

      if ($ShowFailedLogs) {
        Write-Host "`n--- Full log ---" -ForegroundColor DarkYellow
        gh run view $RunId --repo $Repo --log | Out-Host
      }

      throw "GitHub Actions run failed: $concl (RunId $RunId). Open: $runUrl"
    }
  }

  Write-Host ("[{0}] ⏳ {1}..." -f (Get-Date -Format "HH:mm:ss"), $status) -ForegroundColor Gray
  Start-Sleep -Seconds $PollSeconds
}
