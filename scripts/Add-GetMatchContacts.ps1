# Add-GetMatchContacts.ps1
$ErrorActionPreference = "Stop"

$dir = ".\api\GetMatchContacts"
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

module.exports = async function (context, req) {
  let connection = null;
  try {
    const matchIdRaw = (req.query && req.query.matchId) ? req.query.matchId : null;
    const matchId = matchIdRaw ? parseInt(matchIdRaw, 10) : NaN;

    if (!Number.isInteger(matchId) || matchId <= 0) {
      context.res = { status: 400, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: "Use /api/GetMatchContacts?matchId=1" }) };
      return;
    }

    connection = await connectSql();

    const matchRows = await execSql(connection, `
      SELECT TOP (1) Id, ProfileAId, ProfileBId, Status, City, SearchType
      FROM dbo.Matches
      WHERE Id = @m;
    `, [{ name: "m", type: TYPES.Int, value: matchId }]);

    if (!matchRows || matchRows.length === 0) {
      context.res = { status: 404, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: "Match not found" }) };
      return;
    }

    const match = matchRows[0];
    const status = String(match.Status || "");

    if (status !== "Confirmed") {
      context.res = { status: 403, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: `Match not confirmed (status=${status})` }) };
      return;
    }

    const profs = await execSql(connection, `
      SELECT Id, FullName, Email, Phone, FBLink
      FROM dbo.Profiles
      WHERE Id IN (@a, @b);
    `, [
      { name: "a", type: TYPES.Int, value: match.ProfileAId },
      { name: "b", type: TYPES.Int, value: match.ProfileBId }
    ]);

    // Keep response clean
    context.res = {
      status: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        ok: true,
        match: { id: match.Id, city: match.City, searchType: match.SearchType, status },
        contacts: profs.map(p => ({
          id: p.Id,
          fullName: p.FullName,
          email: p.Email,
          phone: p.Phone,
          fbLink: p.FBLink
        }))
      })
    };
  } catch (e) {
    context.log("GetMatchContacts error:", e);
    context.res = { status: 500, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: e.message }) };
  } finally {
    if (connection) connection.close();
  }
};
'@ | Set-Content -Path "$dir\index.js" -Encoding UTF8

git add "$dir\function.json" "$dir\index.js"
git commit -m "Add GetMatchContacts endpoint (only when match is Confirmed)"
git push
