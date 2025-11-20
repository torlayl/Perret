# TimescaleDB Backup and Restore Procedures


```bash
# Backup
./backup.sh

# Restore
./restore.sh backups/tourperret_backup_YYYYMMDD_HHMMSS.dump

# List backups
ls -lht backups/*.dump*

# Check database size
docker exec timescaledb_tourperret psql -U postgres -d tourperret -c \
    "SELECT pg_size_pretty(pg_database_size('tourperret'));"

# Verify backup integrity
docker exec timescaledb_tourperret pg_restore --list \
    /backups/backup_file.dump | head -20
```
