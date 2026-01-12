# Add-IssueOptInTokens.ps1
$ErrorActionPreference = "Stop"

$dir = ".\api\IssueOptInTokens"
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
New-Item -ItemType Directory -Force $dir | Out-Null

@'
{
  "bindings": [
    {
      "authLevel": "anonymous",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["get"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
'@ | Set-Content -Path "$dir\function.json" -Encoding UTF8

@'
const { Connection, Request, TYPES } = require("tedious");
const crypto = require("crypto");

function connectSql() {
  const config = {
    server: process.env.SQL_SERVER,
    authentication: { type: "default", options: { userName: process.env.SQL_USER, password: process.env.SQL_PASSWORD } },
    options: { database: process.env.SQL_DATABASE, encrypt: true, trustServerCertificate: false }
  };

  return new Promise((resolve, reject) => {
    const c = new Connection(config);
    c.on("connect", (err) => (err ? reject(err) : resolve(c)));
    c.connect();
  });
}

function execBatch(connection, sql) {
  return new Promise((resolve, reject) => {
    const req = new Request(sql, (err) => (err ? reject(err) : resolve()));
    connection.execSqlBatch(req);
  });
}

function execSql(connection, sql, params = []) {
  return new Promise((resolve, reject) => {
    const rows = [];
    const req = new Request(sql, (err) => (err ? reject(err) : resolve(rows)));
    for (const p of params) req.addParameter(p.name, p.type, p.value);
    req.on("row", (cols) => {
      const row = {};
      cols.forEach((c) => (row[c.metadata.colName] = c.value));
      rows.push(row);
    });
    connection.execSql(req);
  });
}

function baseUrl(req) {
  const proto = req.headers["x-forwarded-proto"] || "https";
  const host = req.headers["x-forwarded-host"] || req.headers["host"];
  return `${proto}://${host}`;
}

module.exports = async function (context, req) {
  let connection = null;
  try {
    const matchIdRaw = (req.query && req.query.matchId) ? req.query.matchId : null;
    const matchId = matchIdRaw ? parseInt(matchIdRaw, 10) : NaN;

    if (!Number.isInteger(matchId) || matchId <= 0) {
      context.res = { status: 400, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: "Use /api/IssueOptInTokens?matchId=1" }) };
      return;
    }

    connection = await connectSql();

    // Self-heal MatchOptIn table
    await execBatch(connection, `
      IF OBJECT_ID('dbo.MatchOptIn','U') IS NULL
      BEGIN
        CREATE TABLE dbo.MatchOptIn (
          Id INT IDENTITY(1,1) PRIMARY KEY,
          MatchId INT NOT NULL,
          ProfileId INT NOT NULL,
          Token NVARCHAR(200) NOT NULL,
          Answer NVARCHAR(10) NULL,
          AnsweredAt DATETIME2 NULL,
          CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
        CREATE INDEX IX_MatchOptIn_Token ON dbo.MatchOptIn(Token);
      END;
    `);

    // Fetch match
    const m = await execSql(connection, `
      SELECT TOP (1) Id, ProfileAId, ProfileBId, Status, ExpiresAt
      FROM dbo.Matches
      WHERE Id = @m;
    `, [{ name: "m", type: TYPES.Int, value: matchId }]);

    if (!m || m.length === 0) {
      context.res = { status: 404, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: "Match not found" }) };
      return;
    }

    const status = String(m[0].Status || "");
    if (status !== "Pending") {
      context.res = { status: 400, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: `Match status is ${status}, expected Pending` }) };
      return;
    }

    // Reset tokens for this match (idempotent)
    await execSql(connection, `DELETE FROM dbo.MatchOptIn WHERE MatchId = @m;`, [{ name: "m", type: TYPES.Int, value: matchId }]);

    const aId = m[0].ProfileAId;
    const bId = m[0].ProfileBId;

    const tokenA = crypto.randomBytes(24).toString("hex");
    const tokenB = crypto.randomBytes(24).toString("hex");

    await execSql(connection, `
      INSERT INTO dbo.MatchOptIn (MatchId, ProfileId, Token)
      VALUES (@m, @p, @t);
    `, [
      { name: "m", type: TYPES.Int, value: matchId },
      { name: "p", type: TYPES.Int, value: aId },
      { name: "t", type: TYPES.NVarChar, value: tokenA }
    ]);

    await execSql(connection, `
      INSERT INTO dbo.MatchOptIn (MatchId, ProfileId, Token)
      VALUES (@m, @p, @t);
    `, [
      { name: "m", type: TYPES.Int, value: matchId },
      { name: "p", type: TYPES.Int, value: bId },
      { name: "t", type: TYPES.NVarChar, value: tokenB }
    ]);

    const base = baseUrl(req);
    const mk = (tok, ans) => `${base}/api/MatchRespond?token=${encodeURIComponent(tok)}&answer=${ans}`;

    context.res = {
      status: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        ok: true,
        matchId,
        tokens: [
          { profileId: aId, yes: mk(tokenA, "yes"), no: mk(tokenA, "no") },
          { profileId: bId, yes: mk(tokenB, "yes"), no: mk(tokenB, "no") }
        ]
      })
    };
  } catch (e) {
    context.log("IssueOptInTokens error:", e);
    context.res = { status: 500, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: e.message }) };
  } finally {
    if (connection) connection.close();
  }
};
'@ | Set-Content -Path "$dir\index.js" -Encoding UTF8

git add "$dir\function.json" "$dir\index.js"
git commit -m "Add IssueOptInTokens endpoint (generate opt-in links for a match)"
git push
