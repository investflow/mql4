/**
    Logs quotes into MySQL table for every tick.

    Table format:
        CREATE TABLE <instrument-name> (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            quote_time DATETIME(3) NOT NULL,
            bid_price  DECIMAL(10,5) NOT NULL,
            ask_price  DECIMAL(10,5) NOT NULL
        ) ENGINE = InnoDB;
*/

input string mysqlHost = "127.0.0.1"; //MySQL host address. Use IP but not HostName to avoid DNS resolves when opening connections.
input int mysqlPort = 3306; //MySQL server port.
input string mysqlSchema = "quotes"; // Database schema name in MySQL server.
input string mysqlUser = "root"; // MySQL login.
input string mysqlPassword = "12345"; // MySQL password.
input string tableName; // Table name to store quotes. By default Symbol() is used.


// Download mysql driver from here: https://dev.mysql.com/downloads/connector/c/
// Copy libmysql.dll to the Experts folder.
#import "libmysql.dll"
int     mysql_init(int connectId);
int     mysql_errno(int connectId);
int     mysql_error(int connectId);
int     mysql_real_connect(int connectId, uchar & host[], uchar & user[], uchar & password[], uchar & db[], int port, int socket, int clientflag);
int     mysql_real_query(int connectId, uchar & query[], int length);
void    mysql_close(int connectId);
#import

// Connection handle.
int connectId = 0;
// Table name to store data.
string table;

// Expert initialization: opens connection to MySQL.
// Returns INIT_SUCCEEDED if connection can be openend.
int OnInit() {
    if (StringLen(mysqlHost) == 0) {
        Print("Invalid MySQL host");
        return INIT_FAILED;
    }
    if (StringLen(mysqlSchema) == 0) {
        Print("Invalid MySQL database schema");
        return INIT_FAILED;
    }
    if (StringLen(mysqlUser) == 0) {
        Print("Invalid MySQL user");
        return INIT_FAILED;
    }
    if (StringLen(mysqlPassword) == 0) {
        Print("Invalid MySQL password");
        return INIT_FAILED;
    }
    table = StringLen(tableName) > 0 ? tableName : Symbol();

    return reconnect();
}

int reconnect() {
    connectId = mysql_init(connectId);
    if (connectId == 0) {
        Print("mysql_init failed");
        return INIT_FAILED;
    }

    uchar host[];
    StringToCharArray(mysqlHost, host);
    uchar user[];
    StringToCharArray(mysqlUser, user);
    uchar password[];
    StringToCharArray(mysqlPassword, password);
    uchar schema[];
    StringToCharArray(mysqlSchema, schema);

    int unixSocket = 0;
    int clientFlags = 0;
    int rc = mysql_real_connect(connectId, host, user, password, schema, mysqlPort, unixSocket, clientFlags);
    if (rc != connectId) {
        int errno = mysql_errno(connectId);
        Print("mysql_real_connect failed, mysql_errno: ", errno);
        return INIT_FAILED;
    }
    return INIT_SUCCEEDED;
}

// expert deinitialization: closes MySQL connection.
void OnDeinit(const int reason) {
    mysql_close(connectId);
}

// Dump every tick to file.
void OnTick() {
    if (connectId == 0) {
        int rc = reconnect();
        if (rc != INIT_SUCCEEDED) {
            return;
        }
    }
    string statementString = "INSERT INTO " + table + "(quote_time, bid_price, ask_price) VALUES(NOW(3)," + Bid + "," + Ask + ")";
    uchar statement[];
    StringToCharArray(statementString, statement);

    rc = mysql_real_query(connectId, statement, ArraySize(statement));
    if (rc != 0) {
        int errno = mysql_errno(connectId);
        Print("mysql_errno failed, mysql_errno: ", errno);
        connectId = 0;
    }
}
