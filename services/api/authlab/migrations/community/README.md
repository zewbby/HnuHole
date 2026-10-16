# Historical laboratory migration location

The historical lab SQL was promoted unchanged in its constraints to the sole versioned source: `services/api/migrations`. Laboratory fixtures apply the Goose Up portion of that source only inside verified disposable databases. Runtime processes never execute DDL. See the API README for owner/runtime separation and upgrade verification.
