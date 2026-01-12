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
            if (err) { resolve({ status: 500, body: "Connection Error: " + err.message }); }
            
            const sql = "INSERT INTO Profiles (FullName, City, SearchType) VALUES ('Andreas', 'Helsingborg', 'Kvinna'), ('Rebecca', 'Stockholm', 'Man');";
            const request = new Request(sql, (err) => {
                connection.close();
                if (err) resolve({ status: 500, body: "Insert Error: " + err.message });
                else resolve({ status: 200, body: "Datan är nu på plats i databasen!" });
            });
            connection.execSql(request);
        });
        connection.connect();
    });
};
