CREATE TABLE block (
    "NUMBER" INTEGER NOT NULL PRIMARY KEY,
    "HASH" VARCHAR(66),
    "STATE_ROOT" VARCHAR(66),
    "EXTRINSICS_ROOT" VARCHAR(66),
    "PARENT_HASH" VARCHAR(66),
    "DIGEST" text,
    "CREATE_TIME" bigint,
    insert_time timestamp DEFAULT now() NOT NULL
);

CREATE TABLE event (
    id SERIAL NOT NULL PRIMARY KEY,
    "BLOCK_NUMBER" INTEGER NOT NULL REFERENCES block("NUMBER") ON DELETE CASCADE,
    "EVENT" text,
    insert_time timestamp DEFAULT now() NOT NULL
);

CREATE TABLE extrinsic (
    id SERIAL NOT NULL PRIMARY KEY,
    "BLOCK_NUMBER" INTEGER NOT NULL REFERENCES block("NUMBER") ON DELETE CASCADE,
    "EXTRINSIC" text,
    insert_time timestamp DEFAULT now() NOT NULL
);

CREATE TABLE account_identity (
    account_id varchar(50) NOT NULL PRIMARY KEY,
    display varchar(256),
    legal varchar(256),
    web varchar(256),
    riot varchar(256),
    email varchar(256),
    twitter varchar(256)
);