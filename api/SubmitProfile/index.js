const { Connection, Request, TYPES } = require("tedious");
module.exports = async function (context, req) {
    const config = {
        server: process.env.SQL_SERVER,
        authentication: {
            type: "default",
            options: { 
                userName: process.env.SQL_USER, 
                password: process.env.SQL_PASSWORD 
            }
        },
        options: { 
            database: process.env.SQL_DATABASE, 
            encrypt: true, 
            trustServerCertificate: false 
        }
    };
    return new Promise((resolve) => {
        const connection = new Connection(config);
        connection.on("connect", err => {
            if (err) { resolve({ status: 500, body: "Fel vid anslutning" }); return; }
            const { FullName, Email, Phone, Gender, Preference, City, FBLink } = req.body;
            const query = "INSERT INTO Profiles (FullName, Email, Phone, Gender, Preference, City, FBLink) VALUES (@name, @email, @phone, @gender, @pref, @city, @fblink)";
            const request = new Request(query, (err) => {
                connection.close();
                resolve({ status: err ? 500 : 200, body: err ? "Fel vid sparning" : "Success" });
            });
            request.addParameter("name", TYPES.NVarChar, FullName);
            request.addParameter("email", TYPES.NVarChar, Email);
            request.addParameter("phone", TYPES.NVarChar, Phone);
            request.addParameter("gender", TYPES.NVarChar, Gender);
            request.addParameter("pref", TYPES.NVarChar, Preference);
            request.addParameter("city", TYPES.NVarChar, City);
            request.addParameter("fblink", TYPES.NVarChar, FBLink);
            connection.execSql(request);
        });
        connection.connect();
    });
};
