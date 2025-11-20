# Quick Start Guide - Tour Perret TimescaleDB


### 1. Start the Database

```bash
cd ./Perret
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




