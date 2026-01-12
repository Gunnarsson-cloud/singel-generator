$ErrorActionPreference = "Stop"

# --- sanity: repo root ---
if (-not (Test-Path ".git")) { throw "Kör scriptet i repo-roten (där .git ligger)." }

function Ensure-Prop {
  param(
    [Parameter(Mandatory=$true)] $Obj,
    [Parameter(Mandatory=$true)] [string] $Name,
    $DefaultValue
  )
  $has = $Obj.PSObject.Properties.Name -contains $Name
  if (-not $has) {
    $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $DefaultValue
  }
}

# --- 1) Patch staticwebapp.config.json ---
$configPath = "staticwebapp.config.json"
if (-not (Test-Path $configPath)) { '{}' | Set-Content $configPath -Encoding UTF8 }

$cfg = Get-Content $configPath -Raw | ConvertFrom-Json

# navigationFallback
if (-not ($cfg.PSObject.Properties.Name -contains "navigationFallback")) {
  $cfg | Add-Member -NotePropertyName navigationFallback -NotePropertyValue ([pscustomobject]@{})
}

Ensure-Prop $cfg.navigationFallback "rewrite" "/index.html"
Ensure-Prop $cfg.navigationFallback "exclude" @()

# se till att /api/* inte fångas av fallback
if ($cfg.navigationFallback.exclude -notcontains "/api/*") {
  $cfg.navigationFallback.exclude += "/api/*"
}

# routes
Ensure-Prop $cfg "routes" @()

function Upsert-Route($route, $roles, $methods = $null) {
  $existing = $cfg.routes | Where-Object { $_.route -eq $route } | Select-Object -First 1
  if ($existing) {
    $existing.allowedRoles = $roles
    if ($methods) { $existing.methods = $methods }
  } else {
    $r = [pscustomobject]@{ route = $route; allowedRoles = $roles }
    if ($methods) { $r | Add-Member -NotePropertyName methods -NotePropertyValue $methods }
    $cfg.routes += $r
  }
}

Upsert-Route "/admin/*" @("authenticated")
Upsert-Route "/api/*"   @("anonymous") @("GET","POST","DELETE")

($cfg | ConvertTo-Json -Depth 30) | Set-Content $configPath -Encoding UTF8


# --- 2) Patch api/admin/index.js ---
$adminPath = "api/admin/index.js"

$adminJs = @'
const { Connection, Request } = require("tedious");

function runBatch(connection, sql) {
  return new Promise((resolve, reject) => {
    const rows = [];
    const request = new Request(sql, (err) => {
      if (err) return reject(err);
      return resolve(rows);
    });

    request.on("row", (columns) => {
      const row = {};
      columns.forEach((c) => (row[c.metadata.colName] = c.value));
      rows.push(row);
    });

    connection.execSqlBatch(request);
  });
}

module.exports = async function (context, req) {
  try {
    const config = {
      server: process.env.SQL_SERVER,
      authentication: {
        type: "default",
        options: {
          userName: process.env.SQL_USER,
          password: process.env.SQL_PASSWORD,
        },
      },
      options: {
        database: process.env.SQL_DATABASE,
        encrypt: true,
        trustServerCertificate: false,
      },
    };

    const sql = `
      IF OBJECT_ID('dbo.Profiles', 'U') IS NULL
      BEGIN
        CREATE TABLE dbo.Profiles (
          Id INT IDENTITY(1,1) PRIMARY KEY,
          FullName NVARCHAR(200) NULL,
          Email NVARCHAR(320) NULL,
          Phone NVARCHAR(50) NULL,
          Gender NVARCHAR(50) NULL,
          Preference NVARCHAR(50) NULL,
          City NVARCHAR(200) NULL,
          FBLink NVARCHAR(400) NULL,
          SearchType NVARCHAR(50) NULL,
          CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
      END;

      IF NOT EXISTS (SELECT 1 FROM dbo.Profiles)
      BEGIN
        INSERT INTO dbo.Profiles (FullName, City, SearchType)
        VALUES ('Andreas', 'Helsingborg', 'Kvinna'),
               ('Rebecca', 'Stockholm', 'Man');
      END;

      SELECT TOP (200) FullName, City, SearchType
      FROM dbo.Profiles
      ORDER BY Id DESC;
    `;

    const rows = await new Promise((resolve, reject) => {
      const connection = new Connection(config);

      connection.on("connect", async (err) => {
        if (err) {
          connection.close();
          return reject(err);
        }

        try {
          const rows = await runBatch(connection, sql);
          connection.close();
          resolve(rows);
        } catch (e) {
          connection.close();
          reject(e);
        }
      });

      connection.connect();
    });

    context.res = {
      status: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(rows),
    };
  } catch (e) {
    context.log("admin error:", e);
    context.res = {
      status: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ error: e.message }),
    };
  }
};
'@

Set-Content -Path $adminPath -Value $adminJs -Encoding UTF8


# --- 3) (Valfritt men smart) Harden SubmitProfile GET ---
$submitPath = "api/SubmitProfile/index.js"
if (Test-Path $submitPath) {
  $submit = Get-Content $submitPath -Raw

  if ($submit -match 'req\.body' -and $submit -notmatch 'method === "GET"') {
    # Lägg in en enkel GET-guard tidigt i handlern (best effort)
    $submit = $submit -replace '(module\.exports\s*=\s*async\s*function\s*\(context,\s*req\)\s*\{)',
'$1
  if (req.method === "GET") {
    context.res = { status: 200, body: "SubmitProfile live (POST expected)" };
    return;
  }
'
    Set-Content -Path $submitPath -Value $submit -Encoding UTF8
  }
}

# --- 4) Commit + push ---
git status
git add staticwebapp.config.json api/admin/index.js api/SubmitProfile/index.js 2>$null

try {
  git commit -m "Fix /api/admin 404 (JS syntax), exclude /api from fallback, harden SubmitProfile"
} catch {
  Write-Host "Ingen commit behövdes (antingen inga ändringar eller redan committat)."
}

git push

# --- 5) Quick test ---
$base = "https://agreeable-ground-0ee11971e.4.azurestaticapps.net"
"--- API smoke test ---"
Invoke-WebRequest "$base/api/Respond" -Method GET -SkipHttpErrorCheck | Select StatusCode, StatusDescription
Invoke-WebRequest "$base/api/admin" -Method GET -SkipHttpErrorCheck | Select StatusCode, StatusDescription
Invoke-WebRequest "$base/api/SubmitProfile" -Method GET -SkipHttpErrorCheck | Select StatusCode, StatusDescription
