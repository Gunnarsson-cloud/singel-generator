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

module.exports = async function (context, req) {
  let connection = null;
  try {
    const token = (req.query && req.query.token) ? String(req.query.token) : "";
    const answer = (req.query && req.query.answer) ? String(req.query.answer).toLowerCase() : "";

    if (!token || token.length < 10) {
      context.res = { status: 400, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: "Missing/invalid token" }) };
      return;
    }
    if (answer !== "yes" && answer !== "no") {
      context.res = { status: 400, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: "answer must be yes or no" }) };
      return;
    }

    connection = await connectSql();

    // self-heal table
    await execBatch(connection, `
      IF OBJECT_ID('dbo.MatchOptIn','U') IS NULL
      BEGIN
        CREATE TABLE dbo.MatchOptIn (
          Id INT IDENTITY(1,1) PRIMARY KEY,
          MatchId INT NOT NULL,
          ProfileId INT NOT NULL,
          Token NVARCHAR(200) NOT NULL,
          Answer NVARCHAR(10) NULL, -- yes/no
          AnsweredAt DATETIME2 NULL,
          CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
        CREATE INDEX IX_MatchOptIn_Token ON dbo.MatchOptIn(Token);
      END;
    `);

    // Find token row
    const rows = await execSql(connection, `
      SELECT TOP (1) MatchId, ProfileId, Answer
      FROM dbo.MatchOptIn
      WHERE Token = @t
    `, [{ name: "t", type: TYPES.NVarChar, value: token }]);

    if (!rows || rows.length === 0) {
      context.res = { status: 404, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: "Token not found" }) };
      return;
    }

    const matchId = rows[0].MatchId;

    // Update this person's answer (idempotent-ish)
    await execSql(connection, `
      UPDATE dbo.MatchOptIn
      SET Answer = @a, AnsweredAt = SYSUTCDATETIME()
      WHERE Token = @t;
    `, [
      { name: "a", type: TYPES.NVarChar, value: answer },
      { name: "t", type: TYPES.NVarChar, value: token }
    ]);

    // Read both answers
    const all = await execSql(connection, `
      SELECT ProfileId, Answer
      FROM dbo.MatchOptIn
      WHERE MatchId = @m;
    `, [{ name: "m", type: TYPES.Int, value: matchId }]);

    const answers = all.map(x => (x.Answer || "").toLowerCase());
    const hasNo = answers.includes("no");
    const yesCount = answers.filter(x => x === "yes").length;

    if (hasNo) {
      await execSql(connection, `UPDATE dbo.Matches SET Status='Cancelled' WHERE Id=@m;`, [{ name: "m", type: TYPES.Int, value: matchId }]);
      context.res = { status: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ok: true, matchId, status: "Cancelled" }) };
      return;
    }

    if (yesCount >= 2) {
      await execSql(connection, `UPDATE dbo.Matches SET Status='Confirmed' WHERE Id=@m;`, [{ name: "m", type: TYPES.Int, value: matchId }]);
      context.res = { status: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ok: true, matchId, status: "Confirmed" }) };
      return;
    }

    context.res = { status: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ok: true, matchId, status: "Pending" }) };
  } catch (e) {
    context.log("MatchRespond error:", e);
    context.res = { status: 500, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: e.message }) };
  } finally {
    if (connection) connection.close();
  }
};
