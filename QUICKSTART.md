# Quick Start Guide - Tour Perret TimescaleDB

## Step-by-Step Setup (5 Minutes)

### 1. Start the Database

```bash
cd /home/ltor/Nextcloud/LIG/Drakkar/Perret
docker-compose up -d
```

Wait about 10 seconds for initialization.

### 2. Verify Database is Running

```bash
docker ps | grep timescaledb
./query.sh stats
```

You should see the container running and empty statistics.

### 3. Install Python Dependencies

```bash
pip3 install -r requirements.txt
```

### 4. Import Your Data

```bash
# This will take 20-40 minutes for the full 1.6GB file
python3 import_data.py --file ./Data/tourperret.log
```

**Progress will be displayed every 10,000 lines.**

### 5. Query Your Data

```bash
# View statistics
./query.sh stats

# See all devices
./query.sh devices

# Latest readings
./query.sh latest

# Connect to database
./query.sh connect
```

### 6. Create Your First Backup

```bash
./backup.sh
```

Backup will be saved in `./backups/` directory.

---

## Essential Commands

```bash
# Database Management
docker-compose up -d          # Start database
docker-compose down           # Stop database
docker-compose logs -f        # View logs
docker-compose restart        # Restart database

# Data Queries
./query.sh stats              # Database statistics
./query.sh devices            # List all devices
./query.sh latest             # Latest readings
./query.sh temp               # Temperature analysis
./query.sh battery            # Battery status
./query.sh connect            # Open psql

# Backup & Restore
./backup.sh                   # Create backup
./restore.sh backups/xxx.dump # Restore from backup
ls -lht backups/              # List backups

# Data Import
python3 import_data.py --help # See all options
```

---

## Sample Queries in psql

```bash
# Connect to database
./query.sh connect
```

Then run these SQL queries:

```sql
-- Count records
SELECT COUNT(*) FROM sensor_data;

-- View recent data
SELECT time, device_name, temperature, humidity 
FROM sensor_data 
ORDER BY time DESC 
LIMIT 10;

-- Daily averages
SELECT 
    time_bucket('1 day', time) AS day,
    dev_place,
    ROUND(AVG(temperature)::numeric, 1) as avg_temp,
    ROUND(AVG(humidity)::numeric, 1) as avg_humidity
FROM sensor_data
GROUP BY day, dev_place
ORDER BY day DESC
LIMIT 20;

-- Exit
\q
```

---

## Troubleshooting

### Database won't start
```bash
docker-compose down
docker-compose up -d
docker-compose logs
```

### Import fails
```bash
# Check if database is accessible
./query.sh stats

# Check Python dependencies
pip3 install --upgrade psycopg2-binary
```

### Out of disk space
```bash
# Check disk usage
df -h

# Remove old backups
rm backups/old_*.dump.gz

# Compress database
./query.sh connect
# Then: SELECT compress_chunk(i) FROM show_chunks('sensor_data') i;
```

---

## Next Steps

1. **Read the full documentation**: `README.md`
2. **Learn backup procedures**: `BACKUP_RESTORE_PROCEDURES.md`
3. **Explore TimescaleDB**: https://docs.timescale.com/
4. **Setup automated backups**: See README.md "Automated Backup Setup"

---

## Project Structure

```
.
├── Data/
│   └── tourperret.log              # Your sensor data (1.6GB)
├── docker-compose.yml              # Database configuration
├── init-scripts/
│   └── 01_create_schema.sql        # Database schema
├── import_data.py                  # Data import script
├── backup.sh                       # Backup script
├── restore.sh                      # Restore script
├── query.sh                        # Query helper
├── requirements.txt                # Python dependencies
├── README.md                       # Full documentation
├── BACKUP_RESTORE_PROCEDURES.md    # Backup/restore guide
└── QUICKSTART.md                   # This file
```

---

## Important Notes

**Default Password**: The database uses password `postgres` - change this in production!

**Backup Regularly**: Run `./backup.sh` daily or set up automated backups

**Disk Space**: Ensure you have at least 10GB free space

**Data Safety**: Database files are in `./postgres_data/` - don't delete this!

---

**Need Help?** See README.md or BACKUP_RESTORE_PROCEDURES.md for detailed information.
