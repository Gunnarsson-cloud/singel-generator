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
    connection = await connectSql();

    // Expire pending matches past ExpiresAt
    const rows = await execSql(connection, `
      UPDATE dbo.Matches
      SET Status = 'Expired'
      OUTPUT INSERTED.Id AS MatchId
      WHERE Status = 'Pending'
        AND ExpiresAt IS NOT NULL
        AND ExpiresAt < SYSUTCDATETIME();
    `);

    context.res = {
      status: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ok: true, expiredCount: rows.length, expiredMatchIds: rows.map(r => r.MatchId) })
    };
  } catch (e) {
    context.log("ExpireMatches error:", e);
    context.res = { status: 500, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: e.message }) };
  } finally {
    if (connection) connection.close();
  }
};
