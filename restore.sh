#!/bin/bash
#
# Restore script for TimescaleDB Tour Perret database
#
# This script restores a TimescaleDB database backup created with backup.sh
#
# Usage: ./restore.sh <backup_file>
#

set -e  # Exit on error

# Configuration
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-tourperret}"
DB_USER="${DB_USER:-postgres}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Check if backup file is provided
if [ $# -eq 0 ]; then
    error "No backup file specified"
    echo ""
    echo "Usage: $0 <backup_file>"
    echo ""
    echo "Example:"
    echo "  $0 ./backups/tourperret_backup_20231113_120000.dump"
    echo "  $0 ./backups/tourperret_backup_20231113_120000.dump.gz"
    echo ""
    echo "Available backups:"
    ls -lht ./backups/*.dump* 2>/dev/null | head -5 || echo "  No backups found in ./backups/"
    exit 1
fi

BACKUP_FILE="$1"

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    error "Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Decompress if needed
TEMP_FILE=""
if [[ "$BACKUP_FILE" == *.gz ]]; then
    log "Decompressing backup file..."
    TEMP_FILE="${BACKUP_FILE%.gz}"
    gunzip -c "$BACKUP_FILE" > "$TEMP_FILE"
    BACKUP_FILE="$TEMP_FILE"
    log "✓ Decompression complete"
fi

echo "============================================="
echo "TimescaleDB Restore Script"
echo "============================================="
log "Starting restore process..."
log "Database: $DB_NAME"
log "Host: $DB_HOST:$DB_PORT"
log "Backup file: $BACKUP_FILE"

# Ask for confirmation
warn "This will REPLACE all data in database '$DB_NAME'"
read -p "Are you sure you want to continue? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log "Restore cancelled by user"
    [ -n "$TEMP_FILE" ] && rm -f "$TEMP_FILE"
    exit 0
fi

# Check if database is accessible
log "Checking database connection..."
if docker exec timescaledb_tourperret psql -h localhost -U "$DB_USER" -d postgres -c "SELECT 1" > /dev/null 2>&1; then
    log "✓ Database connection successful"
else
    error "✗ Cannot connect to database"
    [ -n "$TEMP_FILE" ] && rm -f "$TEMP_FILE"
    exit 1
fi

# Drop existing database if it exists
log "Dropping existing database (if exists)..."
docker exec timescaledb_tourperret psql -h localhost -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME" || true

# Create fresh database
log "Creating fresh database..."
docker exec timescaledb_tourperret psql -h localhost -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME"

# Copy backup file to container if not already there
CONTAINER_BACKUP_PATH="/backups/$(basename $BACKUP_FILE)"
if [ ! -f "/home/ltor/Nextcloud/LIG/Drakkar/Perret/backups/$(basename $BACKUP_FILE)" ]; then
    log "Copying backup file to container..."
    docker cp "$BACKUP_FILE" "timescaledb_tourperret:$CONTAINER_BACKUP_PATH"
fi

# Restore database
log "Restoring database (this may take a while)..."
if docker exec timescaledb_tourperret pg_restore \
    -h localhost \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    --verbose \
    "$CONTAINER_BACKUP_PATH" \
    2>&1 | tee restore.log; then
    
    log "✓ Restore completed"
else
    warn "Restore completed with warnings (this is normal for TimescaleDB)"
    log "Check restore.log for details"
fi

# Verify restoration
log "Verifying restored database..."
RECORDS=$(docker exec timescaledb_tourperret psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM sensor_data")
log "✓ Records in sensor_data table: $(echo $RECORDS | xargs)"

# Get database statistics
STATS=$(docker exec timescaledb_tourperret psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT 
        'Records: ' || COUNT(*) || 
        ', Date range: ' || MIN(time)::date || ' to ' || MAX(time)::date ||
        ', Devices: ' || COUNT(DISTINCT device_name)
    FROM sensor_data
")
log "Database statistics: $STATS"

# Verify hypertables
HYPERTABLES=$(docker exec timescaledb_tourperret psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT COUNT(*) FROM timescaledb_information.hypertables
")
log "✓ Hypertables: $(echo $HYPERTABLES | xargs)"

# Cleanup temporary file
if [ -n "$TEMP_FILE" ]; then
    rm -f "$TEMP_FILE"
    log "✓ Cleaned up temporary files"
fi

echo ""
echo "============================================="
log "✓ Restore process completed successfully!"
echo "============================================="

exit 0
