let tedious = null;
try {
  tedious = require("tedious");
} catch (e) {
  // Om tedious saknas i deployen vill vi INTE att funktionen försvinner (404).
  // Vi svarar med 500 + tydligt fel istället.
  tedious = null;
}

function runBatch(connection, sql) {
  return new Promise((resolve, reject) => {
    const rows = [];
    const request = new (tedious.Request)(sql, (err) => {
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
  // DELETE /api/profiles?id=123
  if (req.method === "DELETE") {
    const idRaw = (req.query && req.query.id) ? req.query.id : null;
    const id = idRaw ? parseInt(idRaw, 10) : NaN;

    if (!Number.isInteger(id) || id <= 0) {
      context.res = {
        status: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ error: "Missing or invalid id. Use /api/profiles?id=123" })
      };
      return;
    }

    try {
      const tedious = require("tedious");
      const { Connection, Request, TYPES } = tedious;

      const config = {
        server: process.env.SQL_SERVER,
        authentication: {
          type: "default",
          options: { userName: process.env.SQL_USER, password: process.env.SQL_PASSWORD }
        },
        options: { database: process.env.SQL_DATABASE, encrypt: true, trustServerCertificate: false }
      };

      const deleted = await new Promise((resolve, reject) => {
        const connection = new Connection(config);

        connection.on("connect", (err) => {
          if (err) { connection.close(); return reject(err); }

          const sql = "DELETE FROM dbo.Profiles WHERE Id = @Id; SELECT @@ROWCOUNT AS DeletedCount;";
          const request = new Request(sql, (err2) => {
            if (err2) { connection.close(); return reject(err2); }
          });

          request.addParameter("Id", TYPES.Int, id);

          let count = 0;
          request.on("row", (cols) => {
            const col = cols.find(c => c.metadata.colName === "DeletedCount");
            if (col) count = col.value || 0;
          });

          request.on("requestCompleted", () => {
            connection.close();
            resolve(count);
          });

          connection.execSql(request);
        });

        connection.connect();
      });

      context.res = {
        status: 200,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ok: true, id, deleted })
      };
      return;
    } catch (e) {
      context.log("DELETE error:", e);
      context.res = {
        status: 500,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ error: e.message })
      };
      return;
    }
  }
  try {
    if (!tedious) {
      context.res = {
        status: 500,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          error: "Dependency 'tedious' is missing in the deployed API environment.",
          hint: "Ensure the SWA workflow installs API dependencies in /api (npm install) or configure skip_api_build + apiRuntime.",
        }),
      };
      return;
    }

    const { Connection } = tedious;

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

      SELECT TOP (200) Id, FullName, Email, City, FBLink, SearchType
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
          const data = await runBatch(connection, sql);
          connection.close();
          resolve(data);
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




