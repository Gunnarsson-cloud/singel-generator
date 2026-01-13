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
    const body = req.body || {};
    const blockerId = body.blockerId ? parseInt(body.blockerId, 10) : NaN;
    const blockedId = body.blockedId ? parseInt(body.blockedId, 10) : NaN;

    if (!Number.isInteger(blockerId) || blockerId <= 0 || !Number.isInteger(blockedId) || blockedId <= 0) {
      context.res = { status: 400, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: "POST JSON: { blockerId: 14, blockedId: 15 }" }) };
      return;
    }

    if (blockerId === blockedId) {
      context.res = { status: 400, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: "blockerId and blockedId cannot be same" }) };
      return;
    }

    connection = await connectSql();

    // Ensure Blocks table exists + unique constraint for idempotency
    await execBatch(connection, `
      IF OBJECT_ID('dbo.Blocks','U') IS NULL
      BEGIN
        CREATE TABLE dbo.Blocks (
          Id INT IDENTITY(1,1) PRIMARY KEY,
          BlockerProfileId INT NOT NULL,
          BlockedProfileId INT NOT NULL,
          CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        );
      END;

      IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = 'UX_Blocks_Pair' AND object_id = OBJECT_ID('dbo.Blocks')
      )
      BEGIN
        CREATE UNIQUE INDEX UX_Blocks_Pair ON dbo.Blocks(BlockerProfileId, BlockedProfileId);
      END;
    `);

    // Upsert-ish: insert if not exists
    await execSql(connection, `
      IF NOT EXISTS (
        SELECT 1 FROM dbo.Blocks WHERE BlockerProfileId=@a AND BlockedProfileId=@b
      )
      INSERT INTO dbo.Blocks (BlockerProfileId, BlockedProfileId) VALUES (@a, @b);
    `, [
      { name: "a", type: TYPES.Int, value: blockerId },
      { name: "b", type: TYPES.Int, value: blockedId }
    ]);

    context.res = { status: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ok: true, blockerId, blockedId }) };
  } catch (e) {
    context.log("BlockPair error:", e);
    context.res = { status: 500, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: e.message }) };
  } finally {
    if (connection) connection.close();
  }
};
