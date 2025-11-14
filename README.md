# Tour Perret TimescaleDB - Sensor Data Management System

Complete solution for storing, managing, and analyzing IoT sensor data from Tour Perret using TimescaleDB hypertables.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Data Import](#data-import)
- [Querying Data](#querying-data)
- [Backup and Restore](#backup-and-restore)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

This project provides a complete infrastructure to:
- Store 1.6GB+ of IoT sensor data from Tour Perret building
- Use TimescaleDB hypertables for efficient time-series storage
- Enable fast queries on large datasets
- Automate backups and restoration
- Analyze sensor readings over time

### Data Description

The system processes JSON log data from ELSYS EMS sensors deployed at Tour Perret, collecting:
- **Environmental data**: Temperature, humidity, dewpoint
- **Motion sensors**: Acceleration data (x, y, z), motion detection
- **Device metrics**: Battery voltage, signal strength (RSSI, SNR)
- **Location data**: GPS coordinates, gateway information
- **LoRaWAN metadata**: Frequency, data rate, frame counters

---

## ✨ Features

### TimescaleDB Hypertables
- **Automatic partitioning**: Data split into 1-day chunks
- **Chunk skipping**: Faster queries by skipping irrelevant data
- **Compression**: Automatic compression after 7 days
- **Continuous aggregates**: Pre-computed hourly statistics

### Data Management
- **Efficient import**: Batch processing of large JSON files
- **Flexible queries**: Standard SQL with time-series extensions
- **Indexing**: Optimized indexes for common query patterns
- **Raw data preservation**: Original JSON stored for reference

### Operations
- **Automated backups**: Scheduled backup with compression
- **Easy restore**: One-command restoration process
- **Monitoring**: Built-in statistics and health checks
- **Docker deployment**: Containerized for easy setup

---

## 📦 Prerequisites

### Required Software

1. **Docker**: Version 20.10 or higher
   ```bash
   docker --version
   ```

2. **Docker Compose**: Version 2.0 or higher
   ```bash
   docker-compose --version
   ```

3. **Python 3**: Version 3.8 or higher (for data import)
   ```bash
   python3 --version
   ```

4. **PostgreSQL Client Tools** (optional, for manual operations)
   ```bash
   psql --version
   ```

### System Requirements

- **Disk Space**: At least 10GB free (for database + backups)
- **RAM**: 4GB minimum, 8GB recommended
- **CPU**: 2 cores minimum, 4 cores recommended

---

## 🚀 Quick Start

### 1. Clone/Download the Project

```bash
cd /home/ltor/Nextcloud/LIG/Drakkar/Perret
```

### 2. Make Scripts Executable

```bash
chmod +x backup.sh restore.sh
chmod +x import_data.py
```

### 3. Start TimescaleDB

```bash
# Start the database container
docker-compose up -d

# Wait for database to be ready (about 10 seconds)
sleep 10

# Verify it's running
docker ps | grep timescaledb
```

### 4. Initialize Database Schema

The schema is automatically initialized from `init-scripts/01_create_schema.sql` on first startup.

To verify:
```bash
docker exec -it timescaledb_tourperret psql -U postgres -d tourperret -c "\dt"
```

### 5. Import Data

```bash
# Install Python dependencies
pip3 install -r requirements.txt

# Import the log file
python3 import_data.py --file ./Data/tourperret.log
```

### 6. Query Your Data

```bash
docker exec -it timescaledb_tourperret psql -U postgres -d tourperret
```

```sql
-- View latest readings
SELECT * FROM latest_sensor_readings;

-- Count total records
SELECT COUNT(*) FROM sensor_data;
```

---

## 🔧 Detailed Setup

### Step 1: Understanding the Directory Structure

```
/home/ltor/Nextcloud/LIG/Drakkar/Perret/
├── Data/
│   └── tourperret.log          # Your sensor data (1.6GB)
├── docker-compose.yml          # Docker configuration
├── init-scripts/
│   └── 01_create_schema.sql    # Database schema
├── postgres_data/              # Database files (created automatically)
├── backups/                    # Backup storage (created automatically)
├── import_data.py              # Data import script
├── backup.sh                   # Backup script
├── restore.sh                  # Restore script
├── requirements.txt            # Python dependencies
├── BACKUP_RESTORE_PROCEDURES.md # Detailed backup/restore guide
└── README.md                   # This file
```

### Step 2: Configure Docker Compose

The `docker-compose.yml` is pre-configured with optimal settings:

- **Port**: 5432 (PostgreSQL default)
- **Database**: tourperret
- **User**: postgres
- **Password**: postgres (⚠️ Change in production!)

To customize, edit `docker-compose.yml`:

```yaml
environment:
  POSTGRES_USER: your_user
  POSTGRES_PASSWORD: secure_password
  POSTGRES_DB: your_database
```

### Step 3: Start the Database

```bash
# Start in background
docker-compose up -d

# View logs
docker-compose logs -f

# Check health
docker-compose ps
```

The database will:
1. Create the container
2. Initialize PostgreSQL
3. Load TimescaleDB extension
4. Run initialization scripts from `init-scripts/`
5. Create hypertables and indexes

### Step 4: Verify Installation

```bash
# Connect to database
docker exec -it timescaledb_tourperret psql -U postgres -d tourperret

# In psql, run:
\dx                                    # List extensions
SELECT * FROM timescaledb_information.hypertables;  # Check hypertables
\dt                                    # List tables
\q                                     # Exit
```

Expected output:
- Extension: `timescaledb` should be listed
- Hypertable: `sensor_data` should appear
- Tables: `sensor_data`, `sensor_data_hourly` (continuous aggregate)

---

## 📊 Data Import

### Import Process Overview

The `import_data.py` script:
1. Reads JSON log file line by line (memory efficient)
2. Parses each JSON record
3. Extracts sensor data and metadata
4. Batch inserts into database (1000 records at a time)
5. Shows progress and statistics

### Basic Import

```bash
python3 import_data.py
```

This uses default settings:
- File: `./Data/tourperret.log`
- Host: `localhost`
- Port: `5432`
- Database: `tourperret`
- User: `postgres`
- Password: `postgres`
- Batch size: 1000

### Advanced Import Options

```bash
# Custom file location
python3 import_data.py --file /path/to/data.log

# Custom database settings
python3 import_data.py \
    --host localhost \
    --port 5432 \
    --dbname tourperret \
    --user postgres \
    --password postgres

# Larger batch size for faster import
python3 import_data.py --batch-size 5000

# Stop on first error (default: continue on errors)
python3 import_data.py --stop-on-error

# Full example
python3 import_data.py \
    --file ./Data/tourperret.log \
    --batch-size 2000 \
    --dbname tourperret
```

### Import Performance

For the 1.6GB log file:
- **Time**: 20-40 minutes (depending on hardware)
- **Records**: ~millions of sensor readings
- **Batch size**: 1000-5000 recommended
- **Memory**: Low (streaming line-by-line)

### Monitoring Import Progress

The script displays:
```
✓ Connected to database: tourperret
📖 Reading file: ./Data/tourperret.log
📦 Batch size: 1000
⚙️  Processing...

  ✓ Inserted batch: 1,000 records imported so far...
  📊 Processed 10,000 lines (9,987 imported, 13 errors)
  ✓ Inserted batch: 2,000 records imported so far...
  ...
```

### Post-Import Verification

After import completes:

```sql
-- Total records
SELECT COUNT(*) FROM sensor_data;

-- Date range
SELECT MIN(time), MAX(time) FROM sensor_data;

-- Devices and locations
SELECT device_name, dev_place, COUNT(*) 
FROM sensor_data 
GROUP BY device_name, dev_place;

-- Check hypertable chunks
SELECT * FROM timescaledb_information.chunks;
```

---

## 🔍 Querying Data

### TimescaleDB provides powerful time-series functions

### Basic Queries

```sql
-- Latest reading from each device
SELECT * FROM latest_sensor_readings;

-- All readings from last 24 hours
SELECT * FROM sensor_data 
WHERE time > NOW() - INTERVAL '24 hours'
ORDER BY time DESC;

-- Temperature readings for specific device
SELECT time, device_name, temperature, humidity
FROM sensor_data
WHERE device_name = '9fada47dd079acdf46a45421b4e77038'
  AND time > '2021-06-25'
ORDER BY time;
```

### Time Bucket Aggregations

```sql
-- Hourly average temperature per device
SELECT 
    time_bucket('1 hour', time) AS hour,
    device_name,
    AVG(temperature) as avg_temp,
    AVG(humidity) as avg_humidity
FROM sensor_data
WHERE time > NOW() - INTERVAL '7 days'
GROUP BY hour, device_name
ORDER BY hour DESC, device_name;

-- Daily min/max temperatures
SELECT 
    time_bucket('1 day', time) AS day,
    dev_place,
    MIN(temperature) as min_temp,
    MAX(temperature) as max_temp,
    AVG(temperature) as avg_temp
FROM sensor_data
GROUP BY day, dev_place
ORDER BY day DESC;
```

### Using Continuous Aggregates

```sql
-- Query pre-computed hourly statistics (much faster!)
SELECT * FROM sensor_data_hourly
WHERE hour > NOW() - INTERVAL '7 days'
ORDER BY hour DESC;

-- Average battery voltage over time
SELECT 
    hour,
    device_name,
    avg_battery,
    reading_count
FROM sensor_data_hourly
WHERE device_name = '9fada47dd079acdf46a45421b4e77038'
ORDER BY hour DESC;
```

### Advanced Analytics

```sql
-- Temperature trends with moving average
SELECT 
    time_bucket('1 hour', time) AS hour,
    device_name,
    AVG(temperature) as temperature,
    AVG(AVG(temperature)) OVER (
        PARTITION BY device_name 
        ORDER BY time_bucket('1 hour', time)
        ROWS BETWEEN 5 PRECEDING AND CURRENT ROW
    ) as moving_avg
FROM sensor_data
WHERE time > NOW() - INTERVAL '7 days'
GROUP BY hour, device_name
ORDER BY device_name, hour;

-- Detect anomalies (temperature spikes)
SELECT time, device_name, temperature
FROM sensor_data
WHERE temperature > (
    SELECT AVG(temperature) + 3 * STDDEV(temperature)
    FROM sensor_data
)
ORDER BY time DESC;

-- Correlation between sensors
SELECT 
    a.dev_place as location_a,
    b.dev_place as location_b,
    CORR(a.temperature, b.temperature) as temp_correlation
FROM sensor_data a
JOIN sensor_data b ON a.time = b.time
WHERE a.device_name != b.device_name
  AND a.time > NOW() - INTERVAL '30 days'
GROUP BY a.dev_place, b.dev_place;
```

### Query Performance Tips

1. **Always use time filters**: Leverage chunk skipping
   ```sql
   WHERE time > '2021-06-20'  -- Good
   ```

2. **Use continuous aggregates**: For repeated queries
   ```sql
   SELECT * FROM sensor_data_hourly  -- Pre-computed
   ```

3. **Index usage**: Device name and time are indexed
   ```sql
   WHERE device_name = 'xxx' AND time > 'yyy'  -- Fast
   ```

4. **Batch exports**: Use COPY for large extracts
   ```sql
   \copy (SELECT * FROM sensor_data WHERE time > '2021-06-01') TO 'export.csv' CSV HEADER
   ```

---

## 💾 Backup and Restore

### Quick Backup

```bash
# Create backup (includes compression)
./backup.sh
```

Backup files created in `./backups/`:
- `tourperret_backup_YYYYMMDD_HHMMSS.dump` - Main backup
- `tourperret_backup_YYYYMMDD_HHMMSS.dump.gz` - Compressed
- `tourperret_backup_YYYYMMDD_HHMMSS.dump.meta` - Metadata

### Quick Restore

```bash
# List available backups
ls -lht backups/*.dump*

# Restore from backup
./restore.sh backups/tourperret_backup_20231113_120000.dump
```

### Detailed Procedures

See **[BACKUP_RESTORE_PROCEDURES.md](BACKUP_RESTORE_PROCEDURES.md)** for:
- Automated backup setup
- Restore troubleshooting
- Remote backup synchronization
- Selective restore options
- Recovery procedures

---

## 🔧 Maintenance

### Database Maintenance Tasks

#### View Database Statistics

```sql
-- Database size
SELECT pg_size_pretty(pg_database_size('tourperret'));

-- Table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Hypertable information
SELECT * FROM timescaledb_information.hypertables;

-- Chunks information
SELECT 
    chunk_schema,
    chunk_name,
    range_start,
    range_end,
    pg_size_pretty(total_bytes) as size
FROM timescaledb_information.chunks
ORDER BY range_start DESC;
```

#### Compression Status

```sql
-- Check compression settings
SELECT * FROM timescaledb_information.compression_settings;

-- View compressed chunks
SELECT 
    chunk_name,
    pg_size_pretty(before_compression_total_bytes) as uncompressed,
    pg_size_pretty(after_compression_total_bytes) as compressed,
    ROUND(100 - (after_compression_total_bytes::float / 
        before_compression_total_bytes::float * 100), 2) as compression_ratio
FROM timescaledb_information.compressed_chunk_stats
ORDER BY chunk_name;
```

#### Vacuum and Analyze

```bash
# Connect to database
docker exec -it timescaledb_tourperret psql -U postgres -d tourperret

# Run maintenance
VACUUM ANALYZE sensor_data;
```

#### Update Continuous Aggregates

```sql
-- Manually refresh continuous aggregate
CALL refresh_continuous_aggregate('sensor_data_hourly', NULL, NULL);
```

### Container Management

```bash
# View container status
docker-compose ps

# View logs
docker-compose logs -f timescaledb

# Restart container
docker-compose restart

# Stop container
docker-compose stop

# Start container
docker-compose start

# Stop and remove container (data persists)
docker-compose down

# Remove everything including data (DANGEROUS)
docker-compose down -v
```

### Performance Tuning

Edit `docker-compose.yml` to adjust PostgreSQL settings:

```yaml
command:
  - "-c"
  - "shared_buffers=1GB"        # Increase for more RAM
  - "-c"
  - "effective_cache_size=4GB"  # Increase for more RAM
  - "-c"
  - "work_mem=16MB"              # Per-operation memory
```

Then restart:
```bash
docker-compose restart
```

### Data Retention Policy

To automatically drop old data:

```sql
-- Drop chunks older than 90 days
SELECT add_retention_policy('sensor_data', INTERVAL '90 days');

-- View retention policies
SELECT * FROM timescaledb_information.jobs 
WHERE proc_name = 'policy_retention';
```

---

## Troubleshooting

### Database Connection Issues

**Problem**: Cannot connect to database

```bash
# Check if container is running
docker ps | grep timescaledb

# If not running, start it
docker-compose up -d

# Check logs for errors
docker-compose logs timescaledb

# Test connection
docker exec timescaledb_tourperret pg_isready -U postgres
```

### Import Errors

**Problem**: Import script fails with connection error

```bash
# Ensure database is running
docker-compose ps

# Test Python connectivity
python3 -c "import psycopg2; print('psycopg2 installed')"

# Try with verbose error messages
python3 import_data.py --stop-on-error
```

**Problem**: Import is very slow

```bash
# Increase batch size
python3 import_data.py --batch-size 5000

# Check system resources
top
iostat -x 5
```

### Disk Space Issues

**Problem**: Out of disk space

```bash
# Check disk usage
df -h

# Clean old backups
rm backups/tourperret_backup_old*.dump.gz

# Compress database (runs automatically after 7 days)
docker exec timescaledb_tourperret psql -U postgres -d tourperret -c \
    "SELECT compress_chunk(i) FROM show_chunks('sensor_data') i;"
```

### Performance Issues

**Problem**: Queries are slow

```sql
-- Check if indexes are being used
EXPLAIN ANALYZE SELECT * FROM sensor_data WHERE time > NOW() - INTERVAL '1 day';

-- Check for missing indexes
SELECT schemaname, tablename, indexname 
FROM pg_indexes 
WHERE schemaname = 'public';

-- Analyze tables for better query planning
ANALYZE sensor_data;
```

### Container Issues

**Problem**: Container keeps restarting

```bash
# View detailed logs
docker-compose logs --tail=100 timescaledb

# Check for port conflicts
sudo netstat -tulpn | grep 5432

# Try starting with different port
# Edit docker-compose.yml: "5433:5432"
docker-compose up -d
```

### Backup/Restore Issues

See **[BACKUP_RESTORE_PROCEDURES.md](BACKUP_RESTORE_PROCEDURES.md)** for detailed troubleshooting.

---

## Additional Resources

### TimescaleDB Documentation
- [TimescaleDB Docs](https://docs.timescale.com/)
- [Hypertables Guide](https://docs.timescale.com/use-timescale/latest/hypertables/)
- [SQL Functions](https://docs.timescale.com/api/latest/)

### PostgreSQL Documentation
- [PostgreSQL Manual](https://www.postgresql.org/docs/)
- [pg_dump/pg_restore](https://www.postgresql.org/docs/current/backup-dump.html)

### Docker Documentation
- [Docker Compose](https://docs.docker.com/compose/)
- [Docker PostgreSQL](https://hub.docker.com/_/postgres)

---

## Configuration Reference

### Environment Variables

Create a `.env` file to customize settings:

```bash
# Database Configuration
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_secure_password
POSTGRES_DB=tourperret

# Backup Configuration
BACKUP_DIR=./backups
KEEP_DAYS=7

# Import Configuration
DATA_FILE=./Data/tourperret.log
BATCH_SIZE=1000
```

### File Permissions

```bash
# Ensure scripts are executable
chmod +x backup.sh restore.sh import_data.py

# Ensure backup directory is writable
chmod 755 backups

# Secure backup files
chmod 600 backups/*.dump*
```

---

## License

ToDo

---

## Quick Command Reference

```bash
# Start database
docker-compose up -d

# Import data
python3 import_data.py

# Connect to database
docker exec -it timescaledb_tourperret psql -U postgres -d tourperret

# Backup
./backup.sh

# Restore
./restore.sh backups/tourperret_backup_YYYYMMDD_HHMMSS.dump

# Stop database
docker-compose down

# View logs
docker-compose logs -f
```

---

**Last Updated**: November 2025  
**Version**: 1.0
