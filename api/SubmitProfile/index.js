const { Connection, Request } = require('tedious');

module.exports = async function (context, req) {
    const config = {
        server: process.env.SQL_SERVER || 'motes-server-3899.database.windows.net',
        authentication: {
            type: 'default',
            options: {
                userName: 'motesadmin',
                password: 'MatchaMig2026!'
            }
        },
        options: { database: 'MotesDB', encrypt: true, trustServerCertificate: false }
    };

    return new Promise((resolve, reject) => {
        const connection = new Connection(config);
        connection.on('connect', err => {
            if (err) {
                context.log.error(err);
                resolve({ status: 500, body: "Error connecting to SQL" });
            } else {
                const { FullName, Email, Phone, Gender, Preference, City, FBLink } = req.body;
                const query = `INSERT INTO Profiles (FullName, Email, Phone, Gender, Preference, City, FBLink) 
                               VALUES ('${FullName}', '${Email}', '${Phone}', '${Gender}', '${Preference}', '${City}', '${FBLink}')`;
                
                const request = new Request(query, err => {
                    connection.close();
                    if (err) {
                        resolve({ status: 500, body: "Error saving to database" });
                    } else {
                        resolve({ status: 200, body: "Success" });
                    }
                });
                connection.execSql(request);
            }
        });
        connection.connect();
    });
};
