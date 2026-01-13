const { Connection, Request, TYPES } = require("tedious");

function connectSql() {
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

  return new Promise((resolve, reject) => {
    const connection = new Connection(config);
    connection.on("connect", (err) => {
      if (err) return reject(err);
      resolve(connection);
    });
    connection.connect();
  });
}

function execBatch(connection, sql) {
  return new Promise((resolve, reject) => {
    const req = new Request(sql, (err) => {
      if (err) return reject(err);
      resolve();
    });
    connection.execSqlBatch(req);
  });
}

function execSql(connection, sql, params = []) {
  return new Promise((resolve, reject) => {
    const rows = [];
    const req = new Request(sql, (err) => {
      if (err) return reject(err);
      resolve(rows);
    });

    for (const p of params) {
      req.addParameter(p.name, p.type, p.value);
    }

    req.on("row", (cols) => {
      const row = {};
      cols.forEach((c) => (row[c.metadata.colName] = c.value));
      rows.push(row);
    });

    connection.execSql(req);
  });
}

module.exports = async function (context, req) {
  try {
    if (req.method === "GET") {
      context.res = { status: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ok: true, message: "SubmitProfile live (POST expected)" }) };
      return;
    }

    if (req.method !== "POST") {
      context.res = { status: 405, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ error: "Method not allowed" }) };
      return;
    }

    const body = req.body || {};
    const {
      FullName,
      Email,
      Phone,
      Gender,
      Preference,
      City,
      FBLink,
      SearchType,
      ConsentGDPR,
    } = body;

    if (ConsentGDPR !== true) {
      context.res = {
        status: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ error: "Missing GDPR consent. ConsentGDPR must be true." }),
      };
      return;
    }

    const meetingType = (SearchType && String(SearchType).trim()) ? String(SearchType).trim() : "Dejt";

    const connection = await connectSql();

    try {
      // Self-heal columns (safe to run repeatedly)
      const migrateSql = `
        IF COL_LENGTH('dbo.Profiles','ConsentGDPR') IS NULL
          ALTER TABLE dbo.Profiles ADD ConsentGDPR BIT NOT NULL CONSTRAINT DF_Profiles_ConsentGDPR DEFAULT(0);

        IF COL_LENGTH('dbo.Profiles','LastActiveAt') IS NULL
          ALTER TABLE dbo.Profiles ADD LastActiveAt DATETIME2 NULL;

        IF COL_LENGTH('dbo.Profiles','IsPaused') IS NULL
          ALTER TABLE dbo.Profiles ADD IsPaused BIT NOT NULL CONSTRAINT DF_Profiles_IsPaused DEFAULT(0);

        IF COL_LENGTH('dbo.Profiles','IsBanned') IS NULL
          ALTER TABLE dbo.Profiles ADD IsBanned BIT NOT NULL CONSTRAINT DF_Profiles_IsBanned DEFAULT(0);
      `;
      await execBatch(connection, migrateSql);

      const insertSql = `
        INSERT INTO dbo.Profiles
          (FullName, Email, Phone, Gender, Preference, City, FBLink, SearchType, ConsentGDPR, LastActiveAt)
        OUTPUT INSERTED.Id AS Id
        VALUES
          (@fullName, @email, @phone, @gender, @pref, @city, @fb, @searchType, @consent, SYSUTCDATETIME());
      `;

      const rows = await execSql(connection, insertSql, [
        { name: "fullName", type: TYPES.NVarChar, value: FullName ?? null },
        { name: "email", type: TYPES.NVarChar, value: Email ?? null },
        { name: "phone", type: TYPES.NVarChar, value: Phone ?? null },
        { name: "gender", type: TYPES.NVarChar, value: Gender ?? null },
        { name: "pref", type: TYPES.NVarChar, value: Preference ?? null },
        { name: "city", type: TYPES.NVarChar, value: City ?? null },
        { name: "fb", type: TYPES.NVarChar, value: FBLink ?? null },
        { name: "searchType", type: TYPES.NVarChar, value: meetingType },
        { name: "consent", type: TYPES.Bit, value: 1 },
      ]);

      const insertedId = rows?.[0]?.Id ?? null;

      context.res = {
        status: 200,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ok: true, id: insertedId }),
      };
    } finally {
      connection.close();
    }
  } catch (e) {
    context.log("SubmitProfile error:", e);
    context.res = {
      status: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ error: e.message }),
    };
  }
};
