const { Connection, Request, TYPES } = require("tedious");
const config = { 
    server: process.env.SQL_SERVER, 
    authentication: { type: "default", options: { userName: process.env.SQL_USER, password: process.env.SQL_PASSWORD }}, 
    options: { database: process.env.SQL_DATABASE, encrypt: true, trustServerCertificate: false }
};
module.exports = async function (context, req) {
    return new Promise((resolve) => {
        const connection = new Connection(config);
        connection.on("connect", err => {
            if (err) { resolve({ status: 500, body: "DB Error" }); return; }
            let query = req.method === "DELETE" ? "DELETE FROM Profiles WHERE Id = @id" : "SELECT Id, FullName, City, SearchType FROM Profiles";
            const request = new Request(query, (err, rowCount, rows) => {
                connection.close();
                if (err) resolve({ status: 500, body: err.message });
                else if (req.method === "DELETE") resolve({ status: 200 });
                else {
                    const data = rows.map(r => ({ Id: r[0].value, FullName: r[1].value, City: r[2].value, SearchType: r[3].value }));
                    resolve({ body: data, headers: { "Content-Type": "application/json" } });
                }
            });
            if (req.method === "DELETE") request.addParameter("id", TYPES.Int, req.query.id);
            connection.execSql(request);
        });
        connection.connect();
    });
};
