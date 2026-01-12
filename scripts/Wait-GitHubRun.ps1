param(
  [string]$Repo = "Gunnarsson-cloud/singel-generator",
  [int]$PollSeconds = 5,
  [int]$MaxWaitSeconds = 180
)

$ErrorActionPreference = "Stop"

# Matcha på exakt commit SHA så vi tittar på rätt körning
$sha = (git rev-parse HEAD).Trim()
Write-Host "Watching GitHub Actions for repo: $Repo"
Write-Host "Commit: $sha"

$runId = $null
$tries = [Math]::Ceiling($MaxWaitSeconds / $PollSeconds)

for ($i=0; $i -lt $tries; $i++) {
  $runs = gh run list --repo $Repo --limit 20 --json databaseId,headSha,status,createdAt,event | ConvertFrom-Json
  $match = $runs | Where-Object { $_.headSha -eq $sha } | Select-Object -First 1

  if ($match) {
    $runId = $match.databaseId
    break
  }

  Start-Sleep -Seconds $PollSeconds
}

if (-not $runId) {
  throw "Could not find a GitHub Actions run for commit $sha within $MaxWaitSeconds seconds."
}

Write-Host "RunId: $runId"
gh run watch $runId --repo $Repo --exit-status
