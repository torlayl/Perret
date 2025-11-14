#!/bin/bash
#
# Quick query helper for TimescaleDB Tour Perret database
# Provides common queries and statistics
#

DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-tourperret}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Detect if sudo is needed for docker
DOCKER_CMD="docker"
if ! docker ps >/dev/null 2>&1; then
    if sudo docker ps >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    else
        echo -e "${RED}Error: Cannot access Docker. Please ensure Docker is running.${NC}"
        exit 1
    fi
fi

header() {
    echo -e "${BLUE}$1${NC}"
    echo "========================================"
}

query() {
    $DOCKER_CMD exec timescaledb_tourperret psql -U "$DB_USER" -d "$DB_NAME" "$@"
}

if [ "$1" == "stats" ]; then
    header "Database Statistics"
    query -c "
        SELECT 
            'Total Records' as metric,
            COUNT(*)::text as value
        FROM sensor_data
        UNION ALL
        SELECT 
            'Date Range',
            MIN(time)::date::text || ' to ' || MAX(time)::date::text
        FROM sensor_data
        UNION ALL
        SELECT 
            'Days of Data',
            (MAX(time)::date - MIN(time)::date)::text
        FROM sensor_data
        UNION ALL
        SELECT 
            'Unique Devices',
            COUNT(DISTINCT device_name)::text
        FROM sensor_data
        UNION ALL
        SELECT
            'Database Size',
            pg_size_pretty(pg_database_size('$DB_NAME'))
        ;
    "

elif [ "$1" == "devices" ]; then
    header "Devices Summary"
    query -c "
        SELECT 
            device_name,
            dev_place,
            COUNT(*) as records,
            MIN(time)::date as first_reading,
            MAX(time)::date as last_reading
        FROM sensor_data
        GROUP BY device_name, dev_place
        ORDER BY records DESC;
    "

elif [ "$1" == "latest" ]; then
    header "Latest Readings"
    query -c "SELECT * FROM latest_sensor_readings;"

elif [ "$1" == "chunks" ]; then
    header "Hypertable Chunks"
    query -c "
        SELECT 
            chunk_name,
            range_start::date as start_date,
            range_end::date as end_date,
            pg_size_pretty(total_bytes) as size,
            pg_size_pretty(compressed_total_size) as compressed
        FROM timescaledb_information.chunks
        WHERE hypertable_name = 'sensor_data'
        ORDER BY range_start DESC
        LIMIT 20;
    "

elif [ "$1" == "hourly" ]; then
    header "Hourly Statistics (Last 24 Hours)"
    query -c "
        SELECT 
            hour,
            device_name,
            dev_place,
            ROUND(avg_temperature::numeric, 2) as avg_temp,
            ROUND(min_temperature::numeric, 2) as min_temp,
            ROUND(max_temperature::numeric, 2) as max_temp,
            ROUND(avg_humidity::numeric, 1) as avg_humidity,
            reading_count
        FROM sensor_data_hourly
        WHERE hour > NOW() - INTERVAL '24 hours'
        ORDER BY hour DESC, device_name
        LIMIT 50;
    "

elif [ "$1" == "temp" ]; then
    header "Temperature Analysis"
    query -c "
        SELECT 
            dev_place,
            ROUND(AVG(temperature)::numeric, 2) as avg_temp,
            ROUND(MIN(temperature)::numeric, 2) as min_temp,
            ROUND(MAX(temperature)::numeric, 2) as max_temp,
            ROUND(STDDEV(temperature)::numeric, 2) as stddev
        FROM sensor_data
        WHERE temperature IS NOT NULL
        GROUP BY dev_place
        ORDER BY avg_temp DESC;
    "

elif [ "$1" == "battery" ]; then
    header "Battery Status"
    query -c "
        SELECT 
            device_name,
            dev_place,
            MAX(time) as last_reading,
            MAX(vdd) as last_battery_mv,
            AVG(vdd)::integer as avg_battery_mv
        FROM sensor_data
        WHERE vdd IS NOT NULL
        GROUP BY device_name, dev_place
        ORDER BY last_battery_mv ASC;
    "

elif [ "$1" == "connect" ] || [ "$1" == "psql" ]; then
    echo -e "${GREEN}Connecting to database...${NC}"
    $DOCKER_CMD exec -it timescaledb_tourperret psql -U "$DB_USER" -d "$DB_NAME"

elif [ "$1" == "help" ] || [ "$1" == "" ]; then
    echo "TimescaleDB Tour Perret Query Helper"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  stats     - Show database statistics"
    echo "  devices   - List all devices and their data"
    echo "  latest    - Show latest reading from each device"
    echo "  chunks    - Display hypertable chunks"
    echo "  hourly    - Show hourly statistics (last 24h)"
    echo "  temp      - Temperature analysis by location"
    echo "  battery   - Battery status of all devices"
    echo "  connect   - Connect to database (psql)"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 stats"
    echo "  $0 devices"
    echo "  $0 connect"
    echo ""

else
    echo "Unknown command: $1"
    echo "Run '$0 help' for usage information"
    exit 1
fi
