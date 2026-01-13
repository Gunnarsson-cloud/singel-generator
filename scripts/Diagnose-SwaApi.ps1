param(
  [string]$ApiRoot = ".\api"
)

Write-Host "== SWA sanity check ==" -ForegroundColor Cyan

# 1) Node/NPM version (lokalt)
try {
  $nodeV = (& node -v) 2>$null
  $npmV  = (& npm -v) 2>$null
  Write-Host ("Local node: {0} | npm: {1}" -f $nodeV, $npmV)
  if ($nodeV -notmatch "^v18\.") {
    Write-Warning "Du kör INTE Node 18 lokalt. SWA kör Node 18. Vi måste testa med Node 18 för att få samma beteende."
  }
} catch {
  Write-Warning "Kunde inte läsa node/npm-version. Är Node installerat i denna terminal?"
}

# 2) Leta efter mappar som ofta sabbar Functions-host i Azure (backup/test/underscore)
Write-Host "`n-- Suspicious folders under api/ --" -ForegroundColor Yellow
$susp = Get-ChildItem $ApiRoot -Directory -Force | Where-Object {
  $_.Name -match '^_' -or $_.Name -match '\.bak' -or $_.Name -match 'api-test' -or $_.Name -match 'backup'
}

if ($susp) {
  $susp | ForEach-Object {
    $hasFuncJson = Test-Path (Join-Path $_.FullName "function.json")
    Write-Host ("{0}  (function.json: {1})" -f $_.FullName, $hasFuncJson)
  }
  Write-Warning "Om någon av dessa mappar innehåller function.json kan hosten krascha i Azure även om det 'går lokalt'."
} else {
  Write-Host "Inga uppenbara .bak/_/test-mappar hittades i api/."
}

# 3) Kontrollera att function.json -> scriptFile faktiskt finns (och att casing matchar filnamn)
function Test-PathCaseSensitive {
  param([Parameter(Mandatory=$true)][string]$Path)
  $full = (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue)
  if (-not $full) { return $false }

  $p = $full.Path
  $parts = $p -split '[\\/]' | Where-Object { $_ -ne "" }

  # Bygg upp stegvis och verifiera exakt casing per segment
  $cur = if ($p -match '^[A-Za-z]:') { ($parts[0] + "\") } else { "\" }
  $startIndex = if ($p -match '^[A-Za-z]:') { 1 } else { 0 }

  for ($i = $startIndex; $i -lt $parts.Count; $i++) {
    $seg = $parts[$i]
    $children = Get-ChildItem -LiteralPath $cur -Force -ErrorAction SilentlyContinue
    $match = $children | Where-Object { $_.Name -ceq $seg } | Select-Object -First 1
    if (-not $match) { return $false }
    $cur = Join-Path $cur $seg
  }
  return $true
}

Write-Host "`n-- function.json scriptFile checks --" -ForegroundColor Yellow
$funcJsons = Get-ChildItem $ApiRoot -Recurse -Filter "function.json" -File -Force |
             Where-Object { $_.FullName -notmatch "\\node_modules\\|\\\.oryx_" }

$bad = @()
foreach ($fj in $funcJsons) {
  $j = Get-Content $fj.FullName -Raw | ConvertFrom-Json
  if ($j.scriptFile) {
    $scriptPath = Join-Path $fj.Directory.FullName $j.scriptFile
    $exists = Test-Path $scriptPath
    $caseOk = $exists -and (Test-PathCaseSensitive $scriptPath)
    if (-not $exists -or -not $caseOk) {
      $bad += [pscustomobject]@{
        FunctionJson = $fj.FullName
        ScriptFile   = $j.scriptFile
        ResolvedPath = $scriptPath
        Exists       = $exists
        CaseOK       = $caseOk
      }
    }
  }
}

if ($bad.Count -gt 0) {
  Write-Host "`nHITTAT PROBLEM:" -ForegroundColor Red
  $bad | Format-Table -AutoSize
  Write-Warning "På Linux (SWA) är casing känsligt. En enda scriptFile som inte matchar exakt kan få hosten att dö."
} else {
  Write-Host "Alla scriptFile som finns i function.json verkar peka på filer som finns (och casing ser OK ut)."
}

Write-Host "`n== Done ==" -ForegroundColor Cyan

