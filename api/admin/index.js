const { Connection, Request } = require('tedious');

module.exports = async function (context, req) {
    const config = {
        server: process.env.SQL_SERVER,
        authentication: {
            type: 'default',
            options: { userName: process.env.SQL_USER, password: process.env.SQL_PASSWORD }
        },
        options: { database: process.env.SQL_DATABASE, encrypt: true, trustServerCertificate: false }
    };

    return new Promise((resolve) => {
        const connection = new Connection(config);
        connection.on('connect', err => {
            if (err) {
                resolve({ status: 500, body: JSON.stringify({ error: err.message }) });
                return;
            }

            // Denna fråga hämtar data. Om inget finns, kör vi en INSERT och hämtar igen.
            const sql = \
                IF NOT EXISTS (SELECT * FROM Profiles)
                BEGIN
                    INSERT INTO Profiles (FullName, City, SearchType) 
                    VALUES ('Andreas', 'Helsingborg', 'Kvinna'), ('Rebecca', 'Stockholm', 'Man');
                END
                SELECT FullName, City, SearchType FROM Profiles;
            \;

            const results = [];
            const request = new Request(sql, (err) => {
                connection.close();
                if (err) resolve({ status: 500, body: JSON.stringify({ error: err.message }) });
                else resolve({ 
                    status: 200, 
                    headers: { "Content-Type": "application/json" }, 
                    body: JSON.stringify(results) 
                });
            });

            request.on('row', columns => {
                const row = {};
                columns.forEach(col => { row[col.metadata.colName] = col.value; });
                results.push(row);
            });

            connection.execSql(request);
        });
        connection.connect();
    });
};
