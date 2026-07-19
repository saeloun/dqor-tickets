# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## Backups

Production runs `BackupDatabaseJob` hourly. It creates a WAL-safe online SQLite snapshot with `VACUUM INTO`, gzips it, uploads it to `db-backups/YYYY/MM/DD/HHMM.sqlite3.gz` in the configured R2 bucket, and removes backups older than seven days.

Set `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, and `R2_BUCKET`. Run an immediate backup with:

```sh
bin/rails db:backup
```

Restore a backup to a separate file for verification with:

```sh
bin/rails 'db:backup:restore[db-backups/2026/07/19/1200.sqlite3.gz]'
sqlite3 storage/restored.sqlite3 'PRAGMA integrity_check;'
```

Restore never replaces the live database. Stop the app and replace the production database manually only after verifying `storage/restored.sqlite3`.
