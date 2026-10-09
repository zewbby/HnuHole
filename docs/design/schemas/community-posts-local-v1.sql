-- F2 design snapshot only. Exact v1 DDL from PostStore at 514a944.
-- Production migration/initialization remains owned by the Dart PostStore.
CREATE TABLE post_meta(scope TEXT PRIMARY KEY NOT NULL,payload BLOB NOT NULL);
CREATE TABLE post_entries(id TEXT PRIMARY KEY NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),state TEXT NOT NULL,payload BLOB NOT NULL);
CREATE TABLE post_command_index(command_tag TEXT PRIMARY KEY NOT NULL,entry_id TEXT NOT NULL REFERENCES post_entries(id));
