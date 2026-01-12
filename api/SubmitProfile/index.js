const { Connection, Request, TYPES } = require("tedious");
module.exports = async function (context, req) {
  if (req.method === "GET") {
    context.res = { status: 200, body: "SubmitProfile live (POST expected)" };
    return;
  }

            if (ConsentGDPR !== true) {
                resolve({ status: 400, body: "Missing GDPR consent (ConsentGDPR must be true)" });
                return;
            }

    const config = {
        server: process.env.SQL_SERVER,
        authentication: {
            type: "default",
            options: { userName: process.env.SQL_USER, password: process.env.SQL_PASSWORD }
        },
        options: { database: process.env.SQL_DATABASE, encrypt: true, trustServerCertificate: false }
    };
    return new Promise((resolve) => {
        const connection = new Connection(config);
        connection.on("connect", err => {
            if (err) { context.log("DB Error:", err); resolve({ status: 500, body: "DB Fel" }); return; }
            const { FullName, Email, Phone, Gender, Preference, City, FBLink, SearchType, ConsentGDPR } = req.body;
            const meetingType = (SearchType && String(SearchType).trim()) ? String(SearchType).trim() : "Dejt";
            const query = "INSERT INTO Profiles (FullName, Email, Phone, Gender, Preference, City, FBLink, SearchType, ConsentGDPR, LastActiveAt) VALUES (@name, @email, @phone, @gender, @pref, @city, @fblink, @searchType, @consent, SYSUTCDATETIME())";
            const request = new Request(query, (err) => {
                connection.close();
                resolve({ status: err ? 500 : 200, body: err ? "Save Fel" : "Success" });
            });
            request.addParameter("name", TYPES.NVarChar, FullName);
            request.addParameter("email", TYPES.NVarChar, Email);
            request.addParameter("phone", TYPES.NVarChar, Phone);
            request.addParameter("gender", TYPES.NVarChar, Gender);
            request.addParameter("pref", TYPES.NVarChar, Preference);
            
            
            request.addParameter("consent", TYPES.Bit, 1);request.addParameter("searchType", TYPES.NVarChar, meetingType);request.addParameter("city", TYPES.NVarChar, City);
            request.addParameter("fblink", TYPES.NVarChar, FBLink);
            connection.execSql(request);
        });
        connection.connect();
    });
};



