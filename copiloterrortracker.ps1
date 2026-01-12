# ============================================================
# Azure Static Web Apps – Functions Diagnostics (Version 3)
# Kör: powershell -ExecutionPolicy Bypass -File .\SWA_Functions_Diagnostics_v3.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "SWA_Functions_Diagnostics_$timestamp.txt"
$zipTemp = "swa_api_artifact_$timestamp.zip"
$apiPath = ".\api"
$openNotepad = $true

function Log {
    param([string]$text)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value ("[$time] " + $text)
}

function SafeGetContent {
    param([string]$path)
    if (Test-Path $path) {
        try { Get-Content $path -Raw -ErrorAction Stop } catch { return "Kunde inte läsa filen: $path" }
    } else {
        return $null
    }
}

Write-Host "Skapar loggfil: $logFile" -ForegroundColor Cyan
Log "==============================================================="
Log " Azure Static Web Apps – Functions Diagnostics (Version 3)"
Log " Timestamp: $(Get-Date)"
Log "==============================================================="
Log ""

# SECTION 1: Grundläggande repo och api struktur
Log "=== 1. REPO OCH API STRUKTUR ==="
if (Test-Path $apiPath) {
    Log "API-mapp hittad: $apiPath"
    try {
        Get-ChildItem -Path $apiPath -Recurse -Force | Select-Object FullName, Length, Mode | Out-String | ForEach-Object { Log $_ }
    } catch {
        Log "Fel vid listning av api/: $($_.Exception.Message)"
    }
} else {
    Log "❌ API-mappen saknas: $apiPath"
}
Log ""

# SECTION 2: host.json
Log "=== 2. host.json ==="
$hostContent = SafeGetContent "$apiPath/host.json"
if ($hostContent) {
    Log "host.json innehåll:"
    Log $hostContent
} else {
    Log "❌ host.json saknas i $apiPath"
}
Log ""

# SECTION 3: function.json filer
Log "=== 3. function.json filer ==="
$funcFiles = Get-ChildItem -Path $apiPath -Recurse -Filter "function.json" -ErrorAction SilentlyContinue
if ($funcFiles) {
    foreach ($f in $funcFiles) {
        Log ("--- " + $f.FullName + " ---")
        Log (SafeGetContent $f.FullName)
    }
} else {
    Log "❌ Inga function.json hittades under $apiPath"
}
Log ""

# SECTION 4: package.json i api
Log "=== 4. api/package.json ==="
$pkgContent = SafeGetContent "$apiPath/package.json"
if ($pkgContent) {
    Log "package.json (api):"
    Log $pkgContent
    try {
        $pkg = $pkgContent | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Log "⚠️ package.json är inte giltig JSON: $($_.Exception.Message)"
        $pkg = $null
    }
} else {
    Log "❌ package.json saknas i $apiPath"
    $pkg = $null
}
Log ""

# SECTION 5: TypeScript kontroll
Log "=== 5. TypeScript kontroll ==="
if (Test-Path "$apiPath/tsconfig.json") {
    Log "tsconfig.json hittades."
    Log (SafeGetContent "$apiPath/tsconfig.json")
    if (Test-Path "$apiPath/dist") {
        Log "dist/ hittades. Innehåll:"
        Get-ChildItem -Path "$apiPath/dist" -Recurse | Select-Object FullName, Length | Out-String | ForEach-Object { Log $_ }
    } else {
        Log "❌ Ingen dist/ hittades. Om projektet är TypeScript måste du bygga innan deploy."
    }
} else {
    Log "Ingen tsconfig.json – antar JavaScript."
}
Log ""

# SECTION 6: Node och npm
Log "=== 6. Node och npm lokalt ==="
try {
    $nodev = node -v 2>$null
    Log "node version: $nodev"
} catch {
    Log "❌ Node är inte installerat eller inte i PATH."
}
try {
    $npmv = npm -v 2>$null
    Log "npm version: $npmv"
} catch {
    Log "❌ npm är inte installerat eller inte i PATH."
}
Log ""

# SECTION 7: staticwebapp.config.json
Log "=== 7. staticwebapp.config.json ==="
$swaconf = SafeGetContent "./staticwebapp.config.json"
if ($swaconf) {
    Log $swaconf
} else {
    Log "Ingen staticwebapp.config.json hittades i repo-roten."
}
Log ""

# SECTION 8: Tomma JS filer
Log "=== 8. Tomma JS-filer ==="
$emptyJs = @()
if (Test-Path $apiPath) {
    $emptyJs = Get-ChildItem -Path $apiPath -Recurse -Filter "*.js" | Where-Object { $_.Length -eq 0 }
    if ($emptyJs) {
        foreach ($f in $emptyJs) { Log "Tom JS-fil: $($f.FullName)" }
    } else {
        Log "Inga tomma JS-filer hittades."
    }
} else {
    Log "Hoppar över tomma JS-kontroll eftersom api/ saknas."
}
Log ""

# SECTION 9: GitHub Actions workflow
Log "=== 9. GitHub Actions workflow ==="
$wfPath = ".\.github\workflows"
if (Test-Path $wfPath) {
    Get-ChildItem -Path $wfPath -Filter "*.yml" -Recurse | ForEach-Object {
        Log ("--- " + $_.FullName + " ---")
        Log (SafeGetContent $_.FullName)
    }
} else {
    Log "Inga workflow-filer hittades (.github/workflows saknas)."
}
Log ""

# SECTION 10: Valfritt build steg i api
Log "=== 10. Byggsteg i api (valfritt) ==="
# Kontrollera om användaren vill köra build automatiskt
# För att undvika oönskade installationer körs build endast om scriptet startas med parametern -RunBuild
param(
    [switch]$RunBuild = $false,
    [switch]$ForceNpmInstall = $false
)

if ($RunBuild) {
    if (-not (Test-Path $apiPath)) {
        Log "❌ Kan inte köra build: api/ saknas."
    } else {
        Push-Location $apiPath
        try {
            if ($ForceNpmInstall) {
                Log "Kör npm install i api/ (ForceNpmInstall aktiverad)..."
                npm install 2>&1 | ForEach-Object { Log $_ }
            } else {
                # Kör npm ci om package-lock finns, annars npm install
                if (Test-Path "package-lock.json") {
                    Log "Kör npm ci i api/..."
                    npm ci 2>&1 | ForEach-Object { Log $_ }
                } else {
                    Log "Kör npm install i api/..."
                    npm install 2>&1 | ForEach-Object { Log $_ }
                }
            }

            # Kör build om script finns
            if ($pkg -and $pkg.scripts -and $pkg.scripts.build) {
                Log "Kör npm run build i api/..."
                npm run build 2>&1 | ForEach-Object { Log $_ }
            } else {
                Log "Inget build-script definierat i api/package.json. Hoppar över npm run build."
            }
        } catch {
            Log "❌ Fel under build: $($_.Exception.Message)"
        } finally {
            Pop-Location
        }
    }
} else {
    Log "Byggsteg hoppades över. Kör scriptet med -RunBuild för att aktivera npm install och npm run build i api/."
}
Log ""

# SECTION 11: Validera artefakter och skapa zip för simulering
Log "=== 11. Validera artefakter och skapa zip (simulera SWA upload) ==="
if (Test-Path $apiPath) {
    # Bestäm vilka filer som ska ingå: host.json + alla function folders
    $requiredFiles = @()
    if (Test-Path "$apiPath/host.json") { $requiredFiles += "$apiPath/host.json" }
    $functionFolders = Get-ChildItem -Path $apiPath -Directory -ErrorAction SilentlyContinue
    $hasFunctionJson = $false
    foreach ($dir in $functionFolders) {
        if (Test-Path (Join-Path $dir.FullName "function.json")) {
            $hasFunctionJson = $true
            $requiredFiles += (Join-Path $dir.FullName "function.json")
            # include JS files in function folder
            $jsFiles = Get-ChildItem -Path $dir.FullName -Filter "*.js" -Recurse -ErrorAction SilentlyContinue
            foreach ($j in $jsFiles) { $requiredFiles += $j.FullName }
        }
    }

    if (-not $hasFunctionJson) {
        Log "❌ Ingen function.json hittades i några undermappar. SWA förväntar sig function.json per function."
    } else {
        Log "function.json hittades i minst en function‑mapp."
    }

    # Kontrollera att index/main JS finns
    $missingMain = @()
    foreach ($f in $requiredFiles) {
        if (-not (Test-Path $f)) { $missingMain += $f }
    }
    if ($missingMain.Count -gt 0) {
        Log "❌ Följande förväntade filer saknas:"
        foreach ($m in $missingMain) { Log $m }
    } else {
        Log "Alla förväntade filer för paketering finns."
    }

    # Skapa zip
    try {
        if (Test-Path $zipTemp) { Remove-Item $zipTemp -Force }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory((Resolve-Path $apiPath).Path, $zipTemp)
        Log "Skapade zip för api artefakter: $zipTemp"
        # Visa zip innehåll
        $zipList = & powershell -NoProfile -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::OpenRead('$zipTemp').Entries | Select-Object FullName, Length | Format-Table -AutoSize" 2>&1
        foreach ($line in $zipList) { Log $line }
    } catch {
        Log "❌ Kunde inte skapa zip: $($_.Exception.Message)"
    }
} else {
    Log "Hoppar över paketering eftersom api/ saknas."
}
Log ""

# SECTION 12: Försök starta Azure Functions lokalt
Log "=== 12. Försök starta Azure Functions lokalt ==="
if (Get-Command "func" -ErrorAction SilentlyContinue) {
    if (Test-Path $apiPath) {
        Push-Location $apiPath
        try {
            Log "Startar 'func start' i api/ (kör i bakgrunden i 10 sek för att samla logg)."
            $proc = Start-Process -FilePath "func" -ArgumentList "start" -NoNewWindow -RedirectStandardOutput "func_stdout_$timestamp.log" -RedirectStandardError "func_stderr_$timestamp.log" -PassThru
            Start-Sleep -Seconds 10
            if (-not $proc.HasExited) {
                Log "func start körs fortfarande efter 10s. Stoppar processen för att inte blockera."
                $proc | Stop-Process -Force
            }
            if (Test-Path "func_stdout_$timestamp.log") { Log (Get-Content "func_stdout_$timestamp.log" -Raw) }
            if (Test-Path "func_stderr_$timestamp.log") { Log (Get-Content "func_stderr_$timestamp.log" -Raw) }
        } catch {
            Log "❌ Fel vid func start: $($_.Exception.Message)"
        } finally {
            Pop-Location
        }
    } else {
        Log "Hoppar över func start eftersom api/ saknas."
    }
} else {
    Log "Azure Functions Core Tools (func) hittades inte. Installera för att testa lokalt."
}
Log ""

# SECTION 13: ESM / CommonJS kontroll
Log "=== 13. ESM och CommonJS kontroll ==="
if ($pkg) {
    if ($pkg.type -eq "module") {
        Log "package.json anger type: module (ESM). Kontrollera att dina functions använder ESM-syntax eller att Functions runtime stödjer ESM."
    } else {
        Log "package.json saknar type: module eller är CommonJS. Om du använder import/export kan det orsaka runtimefel."
    }
    if ($pkg.main) { Log "package.json main: $($pkg.main)" } else { Log "Ingen 'main' i package.json." }
} else {
    Log "Ingen giltig package.json att analysera för ESM/CommonJS."
}
Log ""

# SECTION 14: Sammanfattande diagnos och rekommendationer
Log "==============================================================="
Log " SAMMANFATTANDE DIAGNOS"
Log "==============================================================="
# Heuristiska kontroller
if (-not (Test-Path $apiPath)) {
    Log "❌ API-mappen saknas. SWA kan inte deploya Functions utan api/."
} else {
    if (-not (Test-Path "$apiPath/host.json")) { Log "❌ host.json saknas." }
    if (-not $funcFiles) { Log "❌ Inga function.json hittades. Kontrollera att varje function har en mapp med function.json och kod." }
    if (-not (Test-Path "$apiPath/package.json")) { Log "❌ package.json saknas i api/." }
    if (Test-Path "$apiPath/tsconfig.json" -and -not (Test-Path "$apiPath/dist")) { Log "❌ TypeScript-projekt utan byggd dist/." }
    if ($emptyJs) { Log "❌ Tomma JS-filer hittades. Ta bort eller fyll i dessa." }
    if (Test-Path $zipTemp) { Log "✅ En zip med api-artefakter skapades för lokal validering: $zipTemp" } else { Log "⚠️ Ingen zip skapad." }
}

Log ""
Log "Rekommendationer:"
Log "- Säkerställ att varje function har en mapp med function.json och en körbar JS-fil (index.js eller main enligt package.json)."
Log "- Om du använder TypeScript: kör build och verifiera att dist/ innehåller JS som deployas."
Log "- Kontrollera package.json för 'type' och 'main' samt att dependencies finns i node_modules vid deploy."
Log "- Kör 'func start' lokalt för att få runtime‑loggar. Om det kraschar lokalt kommer SWA att misslyckas också."
Log "- Om du vill att scriptet kör npm install och npm run build automatiskt, kör scriptet med parametern -RunBuild."
Log ""

Log "==============================================================="
Log " Diagnostics complete."
Log "==============================================================="

# Öppna logg i Notepad
if ($openNotepad) {
    try { Start-Process notepad.exe $logFile } catch { Write-Host "Kunde inte öppna Notepad. Logg sparad som $logFile" -ForegroundColor Yellow }
}

Write-Host "Klar! Loggen är skapad och öppnad i Notepad om möjligt." -ForegroundColor Green
Write-Host "Kör scriptet med -RunBuild för att aktivera npm install och npm run build i api/." -ForegroundColor Cyan
