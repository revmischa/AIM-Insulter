CREATE TABLE IF NOT EXISTS sn (
        sn VARCHAR(16) NOT NULL,
        insulted BOOL DEFAULT FALSE,
        when_insulted INTEGER,
        PRIMARY KEY(sn)
);

CREATE TABLE IF NOT EXISTS sn_info (
        sn VARCHAR(16) NOT NULL,
        updated INT,
        prop VARCHAR(255) NOT NULL,
        value TEXT,
        PRIMARY KEY(sn, prop),
        UNIQUE(sn, prop)
);

CREATE TABLE IF NOT EXISTS im_log (
        sn VARCHAR(16) NOT NULL,
        im_when INTEGER,
        im_to INTEGER,
        other_sn VARCHAR(16),
        message TEXT,
        away INTEGER
);

CREATE TABLE IF NOT EXISTS known (
        sn VARCHAR(16),
        PRIMARY KEY (sn)
);

CREATE TABLE IF NOT EXISTS queue (
        sn VARCHAR(16) NOT NULL UNIQUE,
        added INTEGER NOT NULL,
        pos INTEGER NOT NULL PRIMARY KEY
);
