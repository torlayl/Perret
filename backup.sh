#!/bin/bash
#
# Backup script for TimescaleDB Tour Perret database
#
# This script creates a full backup of the TimescaleDB database including:
# - Schema (tables, hypertables, indexes)
# - Data
# - TimescaleDB specific metadata
#
# The backup is performed using pg_dump in custom format for efficient compression
# and selective restore capabilities.

set -e  # Exit on error

# Configuration
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-tourperret}"
DB_USER="${DB_USER:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/tourperret_backup_${TIMESTAMP}.dump"
LOG_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

echo "============================================="
echo "TimescaleDB Backup Script"
echo "============================================="
log "Starting backup process..."
log "Database: $DB_NAME"
log "Host: $DB_HOST:$DB_PORT"
log "Backup file: $BACKUP_FILE"

# Check if database is accessible
log "Checking database connection..."
if docker exec timescaledb_tourperret psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    log "✓ Database connection successful"
else
    error "✗ Cannot connect to database"
    exit 1
fi

# Get database statistics before backup
log "Gathering database statistics..."
STATS=$(docker exec timescaledb_tourperret psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT 
        (SELECT COUNT(*) FROM sensor_data) as records,
        (SELECT pg_size_pretty(pg_database_size('$DB_NAME'))) as db_size,
        (SELECT COUNT(*) FROM timescaledb_information.hypertables) as hypertables
")
log "Database statistics: $STATS"

# Perform backup using pg_dump
log "Creating backup (this may take a while for large databases)..."
if docker exec timescaledb_tourperret pg_dump \
    -h localhost \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -F c \
    -f "/backups/tourperret_backup_${TIMESTAMP}.dump" \
    --verbose \
    2>> "$LOG_FILE"; then
    
    log "✓ Backup completed successfully"
else
    error "✗ Backup failed"
    exit 1
fi

# Verify backup file exists and get its size
if [ -f "$BACKUP_FILE" ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "✓ Backup file created: $BACKUP_FILE"
    log "  Backup size: $BACKUP_SIZE"
else
    error "✗ Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Create a compressed copy for archival (optional)
log "Creating compressed archive..."
gzip -c "$BACKUP_FILE" > "${BACKUP_FILE}.gz"
COMPRESSED_SIZE=$(du -h "${BACKUP_FILE}.gz" | cut -f1)
log "✓ Compressed backup: ${BACKUP_FILE}.gz"
log "  Compressed size: $COMPRESSED_SIZE"

# Create a metadata file with backup information
METADATA_FILE="${BACKUP_FILE}.meta"
cat > "$METADATA_FILE" << EOF
Backup Metadata
===============
Timestamp: $(date)
Database: $DB_NAME
Host: $DB_HOST:$DB_PORT
User: $DB_USER
Backup File: $BACKUP_FILE
Backup Size: $BACKUP_SIZE
Compressed Size: $COMPRESSED_SIZE
Statistics: $STATS

TimescaleDB Version:
$(docker exec timescaledb_tourperret psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT extversion FROM pg_extension WHERE extname='timescaledb'")

PostgreSQL Version:
$(docker exec timescaledb_tourperret psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT version()")
EOF

log "✓ Metadata file created: $METADATA_FILE"

# List recent backups
log "\nRecent backups in $BACKUP_DIR:"
ls -lht "$BACKUP_DIR"/*.dump 2>/dev/null | head -5 || echo "No previous backups found"

# Optional: Clean up old backups (keep last 7 days)
KEEP_DAYS=7
log "\nCleaning up backups older than $KEEP_DAYS days..."
DELETED_COUNT=$(find "$BACKUP_DIR" -name "tourperret_backup_*.dump*" -type f -mtime +$KEEP_DAYS -delete -print | wc -l)
if [ "$DELETED_COUNT" -gt 0 ]; then
    log "✓ Deleted $DELETED_COUNT old backup file(s)"
else
    log "  No old backups to delete"
fi

echo ""
echo "============================================="
log "✓ Backup process completed successfully!"
echo "============================================="
log "Backup file: $BACKUP_FILE"
log "Compressed:  ${BACKUP_FILE}.gz"
log "Metadata:    $METADATA_FILE"
log "Log file:    $LOG_FILE"

exit 0
