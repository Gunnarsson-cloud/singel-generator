const { Connection, Request, TYPES } = require("tedious");

function connectSql() {
  const config = {
    server: process.env.SQL_SERVER,
    authentication: {
      type: "default",
      options: { userName: process.env.SQL_USER, password: process.env.SQL_PASSWORD }
    },
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

function firstName(fullName) {
  const s = String(fullName ?? "").trim();
  return s ? s.split(/\s+/)[0] : "";
}

function wants(preference, otherGender) {
  const p = String(preference ?? "").toLowerCase();
  const g = String(otherGender ?? "").toLowerCase();

  if (!p) return true; // v1: missing preference => no filter
  if (p.includes("båda") || p.includes("alla")) return true;
  return p.includes(g);
}

module.exports = async function (context, req) {
  let connection = null;

  try {
    connection = await connectSql();

    const migrateSql =
      "IF OBJECT_ID('dbo.Matches','U') IS NULL\n" +
      "BEGIN\n" +
      "  CREATE TABLE dbo.Matches (\n" +
      "    Id INT IDENTITY(1,1) PRIMARY KEY,\n" +
      "    ProfileAId INT NOT NULL,\n" +
      "    ProfileBId INT NOT NULL,\n" +
      "    City NVARCHAR(200) NULL,\n" +
      "    SearchType NVARCHAR(50) NULL,\n" +
      "    Status NVARCHAR(20) NOT NULL DEFAULT('Pending'),\n" +
      "    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),\n" +
      "    ExpiresAt DATETIME2 NULL\n" +
      "  );\n" +
      "END;\n" +
      "\n" +
      "IF OBJECT_ID('dbo.Blocks','U') IS NULL\n" +
      "BEGIN\n" +
      "  CREATE TABLE dbo.Blocks (\n" +
      "    Id INT IDENTITY(1,1) PRIMARY KEY,\n" +
      "    BlockerProfileId INT NOT NULL,\n" +
      "    BlockedProfileId INT NOT NULL,\n" +
      "    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()\n" +
      "  );\n" +
      "END;\n";

    await execBatch(connection, migrateSql);

    const profiles = await execSql(
      connection,
      "SELECT TOP (500) Id, FullName, City, Gender, Preference, SearchType\n" +
        "FROM dbo.Profiles\n" +
        "WHERE ISNULL(ConsentGDPR,0)=1 AND ISNULL(IsPaused,0)=0 AND ISNULL(IsBanned,0)=0\n" +
        "ORDER BY NEWID();"
    );

    if (!profiles || profiles.length < 2) {
      context.res = { status: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ok: true, match: null, reason: "Not enough eligible profiles" }) };
      return;
    }

    const blocks = await execSql(connection, "SELECT BlockerProfileId, BlockedProfileId FROM dbo.Blocks;");
    const blocked = new Set(blocks.map((b) => `${b.BlockerProfileId}:${b.BlockedProfileId}`));

    const prev = await execSql(connection, "SELECT ProfileAId, ProfileBId FROM dbo.Matches;");
    const matched = new Set();
    for (const m of prev) {
      matched.add(`${m.ProfileAId}:${m.ProfileBId}`);
      matched.add(`${m.ProfileBId}:${m.ProfileAId}`);
    }

    const candidates = [];
    for (let i = 0; i < profiles.length; i++) {
      for (let j = i + 1; j < profiles.length; j++) {
        const a = profiles[i];
        const b = profiles[j];

        if (!a.City || !b.City) continue;
        if (String(a.City).toLowerCase() !== String(b.City).toLowerCase()) continue;

        if (!a.SearchType || !b.SearchType) continue;
        if (String(a.SearchType).toLowerCase() !== String(b.SearchType).toLowerCase()) continue;

        if (blocked.has(`${a.Id}:${b.Id}`) || blocked.has(`${b.Id}:${a.Id}`)) continue;
        if (matched.has(`${a.Id}:${b.Id}`)) continue;

        if (!wants(a.Preference, b.Gender)) continue;
        if (!wants(b.Preference, a.Gender)) continue;

        candidates.push([a, b]);
      }
    }

    if (candidates.length === 0) {
      context.res = { status: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ok: true, match: null, reason: "No eligible pair found" }) };
      return;
    }

    const pick = candidates[Math.floor(Math.random() * candidates.length)];
    const a = pick[0];
    const b = pick[1];

    const saved = await execSql(
      connection,
      "INSERT INTO dbo.Matches (ProfileAId, ProfileBId, City, SearchType, Status, ExpiresAt)\n" +
        "VALUES (@a, @b, @city, @stype, 'Pending', DATEADD(hour, 48, SYSUTCDATETIME()));\n" +
        "SELECT SCOPE_IDENTITY() AS MatchId;",
      [
        { name: "a", type: TYPES.Int, value: a.Id },
        { name: "b", type: TYPES.Int, value: b.Id },
        { name: "city", type: TYPES.NVarChar, value: a.City },
        { name: "stype", type: TYPES.NVarChar, value: a.SearchType }
      ]
    );

    const matchId = saved?.[0]?.MatchId ?? null;

    context.res = {
      status: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        ok: true,
        match: {
          matchId,
          city: a.City,
          searchType: a.SearchType,
          a: { id: a.Id, firstName: firstName(a.FullName) },
          b: { id: b.Id, firstName: firstName(b.FullName) }
        }
      })
    };
  } catch (e) {
    context.log("MatchNow error:", e);
    context.res = { status: 500, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: e.message }) };
  } finally {
    if (connection) connection.close();
  }
};
