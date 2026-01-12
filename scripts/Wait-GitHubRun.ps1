[CmdletBinding()]
param(
  [string]$Repo = "",
  [int64]$RunId = 0,
  [int]$TimeoutMinutes = 20,
  [int]$PollSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoFromGit {
  try {
    $url = (git remote get-url origin 2>$null).Trim()
    if (-not $url) { return "" }
    if ($url -match "github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)") {
      return "$($Matches.owner)/$($Matches.repo)"
    }
    return ""
  } catch { return "" }
}

if (-not $Repo) { $Repo = Get-RepoFromGit }
if (-not $Repo) { throw "Repo not specified and could not be inferred from git remote. Provide -Repo 'owner/repo'." }

if (-not $RunId -or $RunId -eq 0) {
  $latest = gh run list --repo $Repo --limit 1 --json databaseId,status,conclusion,htmlUrl,createdAt | ConvertFrom-Json
  if (-not $latest) { throw "No GitHub runs found for $Repo." }
  $RunId = [int64]$latest[0].databaseId
}

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)

Write-Host "Watching GitHub Actions run $RunId in $Repo ..." -ForegroundColor Cyan

while ($true) {
  $run = gh run view $RunId --repo $Repo --json status,conclusion,htmlUrl,displayTitle | ConvertFrom-Json
  $status = $run.status
  $conclusion = $run.conclusion

  Write-Host ("{0}  status={1}  conclusion={2}  title={3}" -f (Get-Date -Format "HH:mm:ss"), $status, $conclusion, $run.displayTitle)

  if ($status -eq "completed") {
    Write-Host "Run completed: $conclusion" -ForegroundColor Yellow
    Write-Host $run.htmlUrl
    if ($conclusion -ne "success") {
      Write-Host "`n--- Failed step logs ---" -ForegroundColor Red
      gh run view $RunId --repo $Repo --log-failed
    }
    break
  }

  if ((Get-Date) -gt $deadline) {
    Write-Host "Timeout after $TimeoutMinutes minutes. Latest status=$status." -ForegroundColor Red
    Write-Host $run.htmlUrl
    break
  }

  Start-Sleep -Seconds $PollSeconds
}
