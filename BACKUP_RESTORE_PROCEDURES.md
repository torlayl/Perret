# TimescaleDB Backup and Restore Procedures

## Table of Contents
1. [Backup Procedures](#backup-procedures)
2. [Restore Procedures](#restore-procedures)
3. [Automated Backup Setup](#automated-backup-setup)
4. [Troubleshooting](#troubleshooting)

---

## Backup Procedures

### Prerequisites
- TimescaleDB container must be running
- Sufficient disk space in the `./backups` directory
- Appropriate permissions to execute backup scripts

### Method 1: Using the Backup Script (Recommended)

The `backup.sh` script automates the entire backup process:

```bash
# Make script executable (first time only)
chmod +x backup.sh

# Run the backup
./backup.sh
```

#### What the Backup Script Does:

1. **Validates Database Connection**: Ensures TimescaleDB is accessible
2. **Collects Statistics**: Records database size, record count, etc.
3. **Creates Backup**: Uses `pg_dump` in custom format
4. **Compresses Backup**: Creates a `.gz` compressed version
5. **Generates Metadata**: Creates a `.meta` file with backup details
6. **Cleanup**: Removes backups older than 7 days (configurable)

#### Backup Output Files:

```
backups/
├── tourperret_backup_20231113_143000.dump       # Main backup file
├── tourperret_backup_20231113_143000.dump.gz    # Compressed backup
├── tourperret_backup_20231113_143000.dump.meta  # Metadata file
└── backup_20231113_143000.log                   # Backup log
```

### Method 2: Manual Backup Using Docker

If you prefer manual control:

```bash
# Create backup directory
mkdir -p backups

# Run pg_dump from inside the container
docker exec timescaledb_tourperret pg_dump \
    -h localhost \
    -U postgres \
    -d tourperret \
    -F c \
    -f /backups/manual_backup_$(date +%Y%m%d_%H%M%S).dump

# Compress the backup
gzip backups/manual_backup_*.dump
```

### Method 3: Backup Specific Tables Only

To backup only the sensor data (not the schema):

```bash
docker exec timescaledb_tourperret pg_dump \
    -h localhost \
    -U postgres \
    -d tourperret \
    -t sensor_data \
    -F c \
    -f /backups/sensor_data_only_$(date +%Y%m%d_%H%M%S).dump
```

### Environment Variables for Backup

You can customize the backup by setting environment variables:

```bash
# Custom configuration
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=tourperret
export DB_USER=postgres
export BACKUP_DIR=./custom_backups

# Run backup with custom settings
./backup.sh
```

---

## Restore Procedures

### IMPORTANT WARNINGS

- **DATA LOSS**: Restoring will **DELETE ALL EXISTING DATA** in the target database
- **BACKUP FIRST**: Always create a backup of the current database before restoring
- **VERIFY BACKUP**: Ensure the backup file is complete and not corrupted
- **STOP APPLICATIONS**: Stop any applications writing to the database

### Method 1: Using the Restore Script (Recommended)

```bash
# Make script executable (first time only)
chmod +x restore.sh

# List available backups
ls -lht backups/*.dump*

# Restore from a backup file
./restore.sh backups/tourperret_backup_20231113_143000.dump

# Or restore from compressed backup
./restore.sh backups/tourperret_backup_20231113_143000.dump.gz
```

#### What the Restore Script Does:

1. **Prompts for Confirmation**: Asks you to confirm before proceeding
2. **Decompresses**: Automatically handles `.gz` files
3. **Drops Database**: Removes the existing database
4. **Creates Fresh Database**: Creates a clean database
5. **Restores Data**: Uses `pg_restore` to import all data
6. **Verifies**: Checks record counts and hypertable configuration

### Method 2: Manual Restore Using Docker

For manual control over the restore process:

#### Step 1: Stop Applications
```bash
# Stop any services using the database
# (Add your application stop commands here)
```

#### Step 2: Drop and Recreate Database
```bash
# Connect to PostgreSQL
docker exec -it timescaledb_tourperret psql -U postgres -d postgres

# In psql prompt:
DROP DATABASE IF EXISTS tourperret;
CREATE DATABASE tourperret;
\q
```

#### Step 3: Restore from Backup
```bash
# If backup is compressed, decompress first
gunzip backups/tourperret_backup_20231113_143000.dump.gz

# Restore the backup
docker exec timescaledb_tourperret pg_restore \
    -h localhost \
    -U postgres \
    -d tourperret \
    --verbose \
    /backups/tourperret_backup_20231113_143000.dump
```

#### Step 4: Verify Restoration
```bash
docker exec timescaledb_tourperret psql -U postgres -d tourperret -c "
    SELECT 
        COUNT(*) as total_records,
        MIN(time) as earliest_date,
        MAX(time) as latest_date,
        COUNT(DISTINCT device_name) as devices
    FROM sensor_data;
"
```

### Method 3: Restore to a Different Database

To restore without affecting the current database:

```bash
# Create a new database with a different name
docker exec timescaledb_tourperret psql -U postgres -d postgres -c \
    "CREATE DATABASE tourperret_restored"

# Restore to the new database
docker exec timescaledb_tourperret pg_restore \
    -h localhost \
    -U postgres \
    -d tourperret_restored \
    --verbose \
    /backups/tourperret_backup_20231113_143000.dump
```

### Method 4: Selective Restore

Restore only specific tables or schemas:

```bash
# List contents of backup file
docker exec timescaledb_tourperret pg_restore \
    --list \
    /backups/tourperret_backup_20231113_143000.dump

# Restore only sensor_data table
docker exec timescaledb_tourperret pg_restore \
    -h localhost \
    -U postgres \
    -d tourperret \
    --table=sensor_data \
    /backups/tourperret_backup_20231113_143000.dump
```

### Restore from Remote Backup

If the backup is on another machine:

```bash
# Copy backup to local backups directory
scp user@remote-host:/path/to/backup.dump ./backups/

# Then restore normally
./restore.sh backups/backup.dump
```

---

## Automated Backup Setup

### Schedule Daily Backups with Cron

```bash
# Edit crontab
crontab -e

# Add line for daily backup at 2 AM
0 2 * * * cd /home/ltor/Nextcloud/LIG/Drakkar/Perret && ./backup.sh >> backups/cron.log 2>&1

# Add line for weekly backup at 3 AM on Sunday
0 3 * * 0 cd /home/ltor/Nextcloud/LIG/Drakkar/Perret && ./backup.sh >> backups/cron.log 2>&1
```

### Create a Systemd Service for Backups

Create `/etc/systemd/system/tourperret-backup.service`:

```ini
[Unit]
Description=Tour Perret TimescaleDB Backup
Wants=tourperret-backup.timer

[Service]
Type=oneshot
User=ltor
WorkingDirectory=/home/ltor/Nextcloud/LIG/Drakkar/Perret
ExecStart=/home/ltor/Nextcloud/LIG/Drakkar/Perret/backup.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Create `/etc/systemd/system/tourperret-backup.timer`:

```ini
[Unit]
Description=Daily Tour Perret Backup Timer
Requires=tourperret-backup.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable tourperret-backup.timer
sudo systemctl start tourperret-backup.timer

# Check status
sudo systemctl status tourperret-backup.timer
```

### Backup to Remote Storage

#### Using rsync to sync backups:

```bash
# Add to backup.sh or run separately
rsync -avz --progress \
    ./backups/ \
    user@backup-server:/path/to/remote/backups/
```

#### Using rclone for cloud storage:

```bash
# Install rclone and configure
rclone copy ./backups/ remote:tourperret-backups/ --progress
```

---

## Troubleshooting

### Backup Issues

#### Problem: "Cannot connect to database"
```bash
# Check if container is running
docker ps | grep timescaledb

# Start container if not running
docker-compose up -d

# Check container logs
docker logs timescaledb_tourperret
```

#### Problem: "Disk full" during backup
```bash
# Check disk space
df -h

# Clean up old backups manually
rm backups/tourperret_backup_202311*.dump.gz

# Or reduce retention in backup.sh (KEEP_DAYS variable)
```

#### Problem: Backup process is very slow
```bash
# Check system resources
top
iostat

# Use parallel dump (modify backup.sh)
pg_dump ... -j 4  # Use 4 parallel jobs
```

### Restore Issues

#### Problem: "Database already exists"
```bash
# Force drop the database
docker exec timescaledb_tourperret psql -U postgres -d postgres -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='tourperret';"
docker exec timescaledb_tourperret psql -U postgres -d postgres -c \
    "DROP DATABASE tourperret;"
```

#### Problem: "Permission denied"
```bash
# Ensure backup files have correct permissions
chmod 644 backups/*.dump
chmod +x backup.sh restore.sh
```

#### Problem: "Extension timescaledb not found"
```bash
# Ensure TimescaleDB extension is enabled
docker exec timescaledb_tourperret psql -U postgres -d tourperret -c \
    "CREATE EXTENSION IF NOT EXISTS timescaledb;"
```

#### Problem: Restore warnings about "already exists"
- These warnings are normal when restoring a TimescaleDB database
- The restore script handles this automatically
- Verify data after restore completes

### Verification After Restore

Run these queries to verify successful restoration:

```sql
-- Check record count
SELECT COUNT(*) FROM sensor_data;

-- Check date range
SELECT MIN(time), MAX(time) FROM sensor_data;

-- Check hypertable configuration
SELECT * FROM timescaledb_information.hypertables;

-- Check chunks
SELECT * FROM timescaledb_information.chunks;

-- Check compression status
SELECT * FROM timescaledb_information.compression_settings;

-- Verify continuous aggregates
SELECT * FROM timescaledb_information.continuous_aggregates;
```

### Recovery from Corrupted Backup

If a backup file is corrupted:

1. Try the compressed version if available:
   ```bash
   ./restore.sh backups/tourperret_backup_20231113_143000.dump.gz
   ```

2. Use an older backup:
   ```bash
   ls -lht backups/*.dump
   ./restore.sh backups/tourperret_backup_20231112_143000.dump
   ```

3. Verify backup integrity before restoring:
   ```bash
   docker exec timescaledb_tourperret pg_restore --list \
       /backups/tourperret_backup_20231113_143000.dump
   ```

---

## Best Practices

1. **Regular Testing**: Test restore procedures regularly (monthly recommended)
2. **Multiple Locations**: Store backups in multiple locations (local + remote)
3. **Versioning**: Keep at least 7 daily backups and 4 weekly backups
4. **Monitoring**: Set up alerts for backup failures
5. **Documentation**: Keep this document updated with any custom procedures
6. **Validation**: Always verify backup integrity after creation
7. **Security**: Encrypt backups containing sensitive data
8. **Off-site**: Maintain off-site backups for disaster recovery

---

## Quick Reference Commands

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
