[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$Repo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Cmd {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Missing command '$Name' in PATH."
  }
}

Assert-Cmd git
Assert-Cmd gh

if (-not (Test-Path ".\api")) { throw "Cannot find .\api - run from repo root." }
if (-not (Test-Path ".\scripts\Wait-GitHubRun.ps1")) { throw "Cannot find .\scripts\Wait-GitHubRun.ps1" }

# 1) Minimal Ping function (no env vars, no external deps)
New-Item -ItemType Directory -Force .\api\Ping | Out-Null

$functionJson = @(
  "{",
  "  ""bindings"": [",
  "    { ""authLevel"": ""anonymous"", ""type"": ""httpTrigger"", ""direction"": ""in"", ""name"": ""req"", ""methods"": [""get""] },",
  "    { ""type"": ""http"", ""direction"": ""out"", ""name"": ""res"" }",
  "  ]",
  "}"
)
$functionJson | Set-Content -Encoding UTF8 .\api\Ping\function.json

$indexJs = @(
  "module.exports = async function (context, req) {",
  "  context.res = {",
  "    status: 200,",
  "    headers: { ""content-type"": ""application/json"" },",
  "    body: { ok: true, name: ""Ping"", ts: new Date().toISOString() }",
  "  };",
  "};"
)
$indexJs | Set-Content -Encoding UTF8 .\api\Ping\index.js

# 2) Disable SendTestEmail temporarily (so it cannot crash deploy/start)
if (Test-Path ".\api\SendTestEmail") {
  if (-not (Test-Path ".\api\_disabled_SendTestEmail")) {
    Rename-Item ".\api\SendTestEmail" "_disabled_SendTestEmail"
    Write-Host "Disabled: api/SendTestEmail -> api/_disabled_SendTestEmail" -ForegroundColor Yellow
  } else {
    Remove-Item ".\api\SendTestEmail" -Recurse -Force
    Write-Host "Removed leftover api/SendTestEmail (disabled copy already exists)" -ForegroundColor Yellow
  }
} else {
  Write-Host "SendTestEmail not found (already disabled?)" -ForegroundColor DarkGray
}

git add -A
$st = git status --porcelain
if (-not $st) {
  Write-Host "No changes to commit." -ForegroundColor DarkGray
} else {
  git commit -m "Isolate Functions: add Ping, disable SendTestEmail" | Out-Host
  git push | Out-Host
}

# 3) Wait for GitHub Actions (so we get the verdict immediately)
$runId = (gh run list --repo $Repo --limit 1 --json databaseId | ConvertFrom-Json).databaseId
.\scripts\Wait-GitHubRun.ps1 -Repo $Repo -RunId $runId
