param(
  [string]$Base = "https://agreeable-ground-0ee11971e.4.azurestaticapps.net",
  [switch]$RunMatchFlow
)

$ErrorActionPreference = "Stop"

function Write-Section($t) { Write-Host ""; Write-Host "=== $t ===" }
function Fail($msg) { throw $msg }

# Requires PowerShell 7+ (we rely on SkipHttpErrorCheck)
if ($PSVersionTable.PSVersion.Major -lt 7) {
  Fail "This script requires PowerShell 7+. You are running: $($PSVersionTable.PSVersion). Start pwsh and run again."
}

function Invoke-Http {
  param(
    [Parameter(Mandatory=$true)][string]$Url,
    [ValidateSet("GET","POST","DELETE")][string]$Method = "GET",
    [string]$Body = $null,
    [string]$ContentType = "application/json"
  )

  if ($Method -eq "GET") {
    return Invoke-WebRequest -Uri $Url -Method GET -UseBasicParsing -SkipHttpErrorCheck
  }
  elseif ($Method -eq "POST") {
    return Invoke-WebRequest -Uri $Url -Method POST -UseBasicParsing -ContentType $ContentType -Body $Body -SkipHttpErrorCheck
  }
  elseif ($Method -eq "DELETE") {
    return Invoke-WebRequest -Uri $Url -Method DELETE -UseBasicParsing -SkipHttpErrorCheck
  }
}

function Invoke-Json {
  param(
    [Parameter(Mandatory=$true)][string]$Url,
    [ValidateSet("GET","POST")][string]$Method = "GET",
    [hashtable]$BodyObj = $null
  )

  $bodyJson = $null
  if ($BodyObj -ne $null) { $bodyJson = ($BodyObj | ConvertTo-Json -Depth 10) }

  $resp = if ($Method -eq "GET") {
    Invoke-Http -Url $Url -Method GET
  } else {
    Invoke-Http -Url $Url -Method POST -Body $bodyJson
  }

  if (-not $resp) { return $null }

  $content = $resp.Content
  if ([string]::IsNullOrWhiteSpace($content)) { return $resp }

  try { return ($content | ConvertFrom-Json) } catch { return $resp }
}

function Retry {
  param(
    [Parameter(Mandatory=$true)][scriptblock]$Action,
    [int]$Tries = 12,
    [int]$SleepSeconds = 5
  )
  for ($i=1; $i -le $Tries; $i++) {
    try { return & $Action }
    catch {
      if ($i -eq $Tries) { throw }
      Start-Sleep -Seconds $SleepSeconds
    }
  }
}

function Get-MatchObj($obj) {
  # Handles both shapes:
  # 1) { matchId, city, ... }
  # 2) { ok, match: { matchId, city, ... } }
  if ($null -eq $obj) { return $null }
  if ($obj.PSObject.Properties.Name -contains "match") { return $obj.match }
  return $obj
}

function Get-TokensFromPayload($payload) {
  # Extract tokens from known properties or from URLs containing token=...
  $tokens = @()

  if ($null -eq $payload) { return @() }

  # If you later return tokens directly, support it
  if ($payload.PSObject.Properties.Name -contains "tokens") {
    $t = $payload.tokens
    if ($t -is [System.Array]) { $tokens += $t }
    else { $tokens += @($t) }
  }

  # Try common direct token fields
  foreach ($name in @("aToken","bToken","tokenA","tokenB")) {
    if ($payload.PSObject.Properties.Name -contains $name) {
      $tokens += @($payload.$name)
    }
  }

  # Fallback: parse token=... from any URLs in the JSON
  $json = ($payload | ConvertTo-Json -Depth 20)
  $m = [regex]::Matches($json, 'token=([^"&\\]+)')
  foreach ($x in $m) { $tokens += $x.Groups[1].Value }

  # Unique + remove empties
  $tokens = $tokens | Where-Object { $_ -and $_.ToString().Trim().Length -gt 0 } | Select-Object -Unique
  return @($tokens)
}

Write-Host "Base: $Base"
Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
$stamp = (Get-Date -Format "yyyyMMdd-HHmmss")
$rand  = ([Guid]::NewGuid().ToString("N")).Substring(0,6)

# 1) Frontend check
Write-Section "Frontend check"
$homeResp = Retry -Tries 6 -SleepSeconds 3 -Action { Invoke-Http -Url "$Base/" -Method GET }
Write-Host "HTTP: $($homeResp.StatusCode)"
if ($homeResp.StatusCode -ne 200) { Fail "Home page not 200." }

if ($homeResp.Content -match "infobox-title") { Write-Host "PASS: infobox-title found" }
else { Write-Host "WARN: infobox-title NOT found (deploy might still be propagating)" }

# 2) Profiles list
Write-Section "GET /api/profiles"
$profiles = Retry -Tries 12 -SleepSeconds 5 -Action { Invoke-Json -Url "$Base/api/profiles" -Method GET }
if ($null -eq $profiles) { Fail "Profiles response is null." }

# If JSON parsing failed, we got a web response object
if ($profiles.PSObject.Properties.Name -contains "StatusCode") {
  Write-Host "HTTP: $($profiles.StatusCode)"
  Write-Host $profiles.Content
  Fail "GET /api/profiles did not return JSON."
}

$profileCount = @($profiles).Count
Write-Host "PASS: profiles returned. Count=$profileCount"

# 3) Create two test profiles (unique city so matching is deterministic)
Write-Section "POST /api/SubmitProfile (2 test profiles)"
$testCity = "ZZZ-Smoke-$stamp-$rand"
$maleEmail   = "smoke.m.$stamp.$rand@example.com"
$femaleEmail = "smoke.f.$stamp.$rand@example.com"

$male = @{
  FullName    = "Smoke Test Man $stamp"
  Email       = $maleEmail
  Phone       = "0700000001"
  City        = $testCity
  Gender      = "Man"
  Preference  = "En kvinna"
  FBLink      = "https://facebook.com/smoke.test"
  SearchType  = "Kul möte"
  ConsentGDPR = $true
}

$female = @{
  FullName    = "Smoke Test Kvinna $stamp"
  Email       = $femaleEmail
  Phone       = "0700000002"
  City        = $testCity
  Gender      = "Kvinna"
  Preference  = "En man"
  FBLink      = "https://facebook.com/smoke.test"
  SearchType  = "Kul möte"
  ConsentGDPR = $true
}

$resp1 = Retry -Tries 12 -SleepSeconds 5 -Action { Invoke-Http -Url "$Base/api/SubmitProfile" -Method POST -Body ($male | ConvertTo-Json -Depth 10) }
$resp2 = Retry -Tries 12 -SleepSeconds 5 -Action { Invoke-Http -Url "$Base/api/SubmitProfile" -Method POST -Body ($female | ConvertTo-Json -Depth 10) }

Write-Host "SubmitProfile status: $($resp1.StatusCode), $($resp2.StatusCode)"
if ($resp1.StatusCode -ge 400 -or $resp2.StatusCode -ge 400) {
  Write-Host "Body1: $($resp1.Content)"
  Write-Host "Body2: $($resp2.Content)"
  Fail "SubmitProfile failed."
}
Write-Host "PASS: SubmitProfile ok"

# Resolve IDs
Write-Section "Resolve new profile IDs"
$profiles2 = Retry -Tries 12 -SleepSeconds 5 -Action { Invoke-Json -Url "$Base/api/profiles" -Method GET }
$maleRow   = @($profiles2) | Where-Object { $_.Email -eq $maleEmail }   | Select-Object -First 1
$femaleRow = @($profiles2) | Where-Object { $_.Email -eq $femaleEmail } | Select-Object -First 1
if (-not $maleRow -or -not $femaleRow) { Fail "Could not find newly created profiles via GET /api/profiles." }

$maleId = $maleRow.Id
$femaleId = $femaleRow.Id
Write-Host "PASS: maleId=$maleId femaleId=$femaleId city=$testCity"

# 4) OPTIONAL: Match flow
if ($RunMatchFlow) {
  Write-Section "POST /api/MatchNow (writes to DB)"
  $matchResp = Retry -Tries 12 -SleepSeconds 5 -Action { Invoke-Json -Url "$Base/api/MatchNow" -Method POST }

  $matchObj = Get-MatchObj $matchResp
  if (-not $matchObj -or -not $matchObj.matchId) {
    Write-Host "Raw MatchNow payload:"
    Write-Host ($matchResp | ConvertTo-Json -Depth 20)
    Fail "MatchNow did not return matchId (neither matchId nor match.matchId)."
  }

  $matchId = $matchObj.matchId
  $matchCity = $matchObj.city
  $matchType = $matchObj.searchType

  Write-Host "matchId: $matchId"
  Write-Host "city: $matchCity"
  Write-Host "searchType: $matchType"
  if ($matchObj.a) { Write-Host ("a.id: " + $matchObj.a.id) }
  if ($matchObj.b) { Write-Host ("b.id: " + $matchObj.b.id) }

  if ($matchCity -ne $testCity) {
    Fail "MatchNow returned city '$matchCity' but expected unique test city '$testCity'."
  }
  Write-Host "PASS: MatchNow matched the smoke-test city (deterministic)"

  Write-Section "GET /api/IssueOptInTokens"
  $tokensPayload = Retry -Tries 12 -SleepSeconds 5 -Action { Invoke-Json -Url "$Base/api/IssueOptInTokens?matchId=$matchId" -Method GET }

  $tokensJson = ($tokensPayload | ConvertTo-Json -Depth 20)
  if ($tokensJson -match "azurewebsites\.net") { Write-Host "WARN: Opt-in links include azurewebsites.net (canonical links backlog item)" }
  else { Write-Host "PASS: No azurewebsites.net detected in token payload (or links not present)" }

  $tokens = Get-TokensFromPayload $tokensPayload
  if (@($tokens).Count -lt 2) {
    Write-Host "Token payload:"
    Write-Host $tokensJson
    Fail "Could not extract two tokens from IssueOptInTokens response."
  }

  $token1 = $tokens[0]
  $token2 = $tokens[1]
  Write-Host "PASS: Extracted two tokens"

  Write-Section "GET /api/MatchRespond (yes/yes)"
  $r1 = Retry -Tries 12 -SleepSeconds 5 -Action { Invoke-Json -Url "$Base/api/MatchRespond?token=$token1&answer=yes" -Method GET }
  $r2 = Retry -Tries 12 -SleepSeconds 5 -Action { Invoke-Json -Url "$Base/api/MatchRespond?token=$token2&answer=yes" -Method GET }
  Write-Host ("Response1: " + ($r1 | ConvertTo-Json -Depth 20))
  Write-Host ("Response2: " + ($r2 | ConvertTo-Json -Depth 20))

  Write-Section "GET /api/GetMatchContacts"
  $contacts = Retry -Tries 12 -SleepSeconds 5 -Action { Invoke-Json -Url "$Base/api/GetMatchContacts?matchId=$matchId" -Method GET }
  $contactsJson = ($contacts | ConvertTo-Json -Depth 20)
  Write-Host $contactsJson

  if ($contactsJson -match $maleEmail -and $contactsJson -match $femaleEmail) {
    Write-Host "PASS: Contacts returned for both profiles"
  } else {
    Write-Host "WARN: Contacts returned but could not confirm both emails in payload"
  }
} else {
  Write-Host ""
  Write-Host "NOTE: Skipping MatchNow/Opt-in flow (safe mode). To run full flow: .\scripts\Smoke-Test.ps1 -RunMatchFlow"
}

# 5) ExpireMatches
Write-Section "GET /api/ExpireMatches"
$exp = Retry -Tries 12 -SleepSeconds 5 -Action { Invoke-Json -Url "$Base/api/ExpireMatches" -Method GET }
Write-Host ($exp | ConvertTo-Json -Depth 20)
Write-Host "PASS: ExpireMatches responded"

# 6) Cleanup (best-effort)
Write-Section "Cleanup (best-effort delete test profiles)"
$del1 = Retry -Tries 3 -SleepSeconds 2 -Action { Invoke-Http -Url "$Base/api/profiles?id=$maleId" -Method DELETE }
$del2 = Retry -Tries 3 -SleepSeconds 2 -Action { Invoke-Http -Url "$Base/api/profiles?id=$femaleId" -Method DELETE }
Write-Host "DELETE status: $($del1.StatusCode), $($del2.StatusCode)"
if ($del1.StatusCode -ge 400 -or $del2.StatusCode -ge 400) {
  Write-Host "WARN: Delete may require auth; delete from /admin later if needed."
} else {
  Write-Host "PASS: Test profiles deleted"
}

Write-Host ""
Write-Host "ALL DONE. Smoke test finished."
Write-Host "Test city: $testCity"
