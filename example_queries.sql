-- Example SQL Queries for Tour Perret Sensor Data
-- Connect with: ./query.sh connect
-- Or: docker exec -it timescaledb_tourperret psql -U postgres -d tourperret

-- ============================================
-- BASIC STATISTICS
-- ============================================

-- Total number of records
SELECT COUNT(*) as total_records FROM sensor_data;

-- Date range of data
SELECT 
    MIN(time)::date as earliest_date,
    MAX(time)::date as latest_date,
    (MAX(time)::date - MIN(time)::date) as days_of_data
FROM sensor_data;

-- Records per device
SELECT 
    device_name,
    dev_place,
    COUNT(*) as record_count,
    MIN(time)::date as first_reading,
    MAX(time)::date as last_reading
FROM sensor_data
GROUP BY device_name, dev_place
ORDER BY record_count DESC;

-- Database size
SELECT pg_size_pretty(pg_database_size('tourperret')) as database_size;


-- ============================================
-- LATEST READINGS
-- ============================================

-- Latest reading from each device (using pre-built view)
SELECT * FROM latest_sensor_readings;

-- Latest 10 readings across all devices
SELECT 
    time,
    device_name,
    dev_place,
    temperature,
    humidity,
    vdd as battery_mv
FROM sensor_data
ORDER BY time DESC
LIMIT 10;


-- ============================================
-- TEMPERATURE ANALYSIS
-- ============================================

-- Average temperature by location
SELECT 
    dev_place,
    COUNT(*) as readings,
    ROUND(AVG(temperature)::numeric, 2) as avg_temp,
    ROUND(MIN(temperature)::numeric, 2) as min_temp,
    ROUND(MAX(temperature)::numeric, 2) as max_temp,
    ROUND(STDDEV(temperature)::numeric, 2) as std_dev
FROM sensor_data
WHERE temperature IS NOT NULL
GROUP BY dev_place
ORDER BY avg_temp DESC;

-- Daily temperature trends
SELECT 
    time_bucket('1 day', time) AS day,
    dev_place,
    ROUND(AVG(temperature)::numeric, 2) as avg_temp,
    ROUND(MIN(temperature)::numeric, 2) as min_temp,
    ROUND(MAX(temperature)::numeric, 2) as max_temp
FROM sensor_data
WHERE temperature IS NOT NULL
GROUP BY day, dev_place
ORDER BY day DESC, dev_place
LIMIT 30;

-- Hourly temperature (last 24 hours)
SELECT 
    time_bucket('1 hour', time) AS hour,
    device_name,
    ROUND(AVG(temperature)::numeric, 2) as avg_temp
FROM sensor_data
WHERE time > NOW() - INTERVAL '24 hours'
  AND temperature IS NOT NULL
GROUP BY hour, device_name
ORDER BY hour DESC;

-- Temperature extremes
SELECT 
    time,
    device_name,
    dev_place,
    temperature
FROM sensor_data
WHERE temperature = (SELECT MAX(temperature) FROM sensor_data)
   OR temperature = (SELECT MIN(temperature) FROM sensor_data)
ORDER BY temperature DESC;


-- ============================================
-- HUMIDITY ANALYSIS
-- ============================================

-- Average humidity by location
SELECT 
    dev_place,
    ROUND(AVG(humidity)::numeric, 1) as avg_humidity,
    ROUND(MIN(humidity)::numeric, 1) as min_humidity,
    ROUND(MAX(humidity)::numeric, 1) as max_humidity
FROM sensor_data
WHERE humidity IS NOT NULL
GROUP BY dev_place
ORDER BY avg_humidity DESC;

-- Daily humidity trends
SELECT 
    time_bucket('1 day', time) AS day,
    dev_place,
    ROUND(AVG(humidity)::numeric, 1) as avg_humidity
FROM sensor_data
WHERE humidity IS NOT NULL
GROUP BY day, dev_place
ORDER BY day DESC, dev_place
LIMIT 30;


-- ============================================
-- BATTERY MONITORING
-- ============================================

-- Current battery status
SELECT 
    device_name,
    dev_place,
    MAX(time) as last_reading,
    MAX(vdd) as current_battery_mv,
    CASE 
        WHEN MAX(vdd) > 3500 THEN 'Good'
        WHEN MAX(vdd) > 3200 THEN 'Fair'
        ELSE 'Low'
    END as battery_status
FROM sensor_data
WHERE vdd IS NOT NULL
GROUP BY device_name, dev_place
ORDER BY current_battery_mv ASC;

-- Battery voltage over time
SELECT 
    time_bucket('1 day', time) AS day,
    device_name,
    AVG(vdd)::integer as avg_battery_mv
FROM sensor_data
WHERE vdd IS NOT NULL
GROUP BY day, device_name
ORDER BY day DESC, device_name
LIMIT 50;


-- ============================================
-- MOTION DETECTION
-- ============================================

-- Motion events summary
SELECT 
    device_name,
    dev_place,
    COUNT(*) FILTER (WHERE acc_motion > 0) as motion_events,
    COUNT(*) as total_readings,
    ROUND(100.0 * COUNT(*) FILTER (WHERE acc_motion > 0) / COUNT(*), 2) as motion_percentage
FROM sensor_data
GROUP BY device_name, dev_place
ORDER BY motion_events DESC;

-- Recent motion events
SELECT 
    time,
    device_name,
    dev_place,
    acc_motion,
    x, y, z
FROM sensor_data
WHERE acc_motion > 50
ORDER BY time DESC
LIMIT 20;


-- ============================================
-- SIGNAL QUALITY
-- ============================================

-- Average RSSI by device
SELECT 
    device_name,
    dev_place,
    ROUND(AVG(rssi)::numeric, 1) as avg_rssi,
    ROUND(AVG(lora_snr)::numeric, 1) as avg_snr,
    COUNT(*) as readings
FROM sensor_data
WHERE rssi IS NOT NULL
GROUP BY device_name, dev_place
ORDER BY avg_rssi DESC;

-- Poor signal quality readings
SELECT 
    time,
    device_name,
    dev_place,
    rssi,
    lora_snr
FROM sensor_data
WHERE rssi < -100 OR lora_snr < 0
ORDER BY time DESC
LIMIT 50;


-- ============================================
-- TIME-SERIES AGGREGATIONS (Using TimescaleDB features)
-- ============================================

-- Use pre-computed hourly statistics (faster!)
SELECT * 
FROM sensor_data_hourly
WHERE hour > NOW() - INTERVAL '7 days'
ORDER BY hour DESC, device_name
LIMIT 100;

-- 15-minute intervals
SELECT 
    time_bucket('15 minutes', time) AS interval,
    device_name,
    ROUND(AVG(temperature)::numeric, 2) as avg_temp,
    ROUND(AVG(humidity)::numeric, 1) as avg_humidity,
    COUNT(*) as reading_count
FROM sensor_data
WHERE time > NOW() - INTERVAL '24 hours'
GROUP BY interval, device_name
ORDER BY interval DESC, device_name;

-- Weekly aggregations
SELECT 
    time_bucket('1 week', time) AS week,
    dev_place,
    ROUND(AVG(temperature)::numeric, 2) as avg_temp,
    ROUND(AVG(humidity)::numeric, 1) as avg_humidity,
    COUNT(*) as readings
FROM sensor_data
GROUP BY week, dev_place
ORDER BY week DESC, dev_place;


-- ============================================
-- ADVANCED ANALYTICS
-- ============================================

-- Moving average (7-day temperature)
SELECT 
    time_bucket('1 day', time) AS day,
    device_name,
    ROUND(AVG(temperature)::numeric, 2) as daily_avg_temp,
    ROUND(AVG(AVG(temperature)) OVER (
        PARTITION BY device_name 
        ORDER BY time_bucket('1 day', time)
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    )::numeric, 2) as moving_avg_7day
FROM sensor_data
WHERE temperature IS NOT NULL
GROUP BY day, device_name
ORDER BY day DESC, device_name
LIMIT 100;

-- Temperature anomalies (more than 2 standard deviations)
WITH stats AS (
    SELECT 
        device_name,
        AVG(temperature) as mean_temp,
        STDDEV(temperature) as stddev_temp
    FROM sensor_data
    WHERE temperature IS NOT NULL
    GROUP BY device_name
)
SELECT 
    s.time,
    s.device_name,
    s.dev_place,
    s.temperature,
    st.mean_temp,
    ABS(s.temperature - st.mean_temp) / st.stddev_temp as std_deviations
FROM sensor_data s
JOIN stats st ON s.device_name = st.device_name
WHERE ABS(s.temperature - st.mean_temp) > 2 * st.stddev_temp
ORDER BY time DESC
LIMIT 50;

-- Correlation between temperature and humidity
SELECT 
    dev_place,
    ROUND(CORR(temperature, humidity)::numeric, 3) as temp_humidity_correlation,
    COUNT(*) as sample_size
FROM sensor_data
WHERE temperature IS NOT NULL 
  AND humidity IS NOT NULL
GROUP BY dev_place;


-- ============================================
-- DATA QUALITY CHECKS
-- ============================================

-- Null value counts
SELECT 
    'temperature' as field,
    COUNT(*) FILTER (WHERE temperature IS NULL) as null_count,
    COUNT(*) as total_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE temperature IS NULL) / COUNT(*), 2) as null_percentage
FROM sensor_data
UNION ALL
SELECT 
    'humidity',
    COUNT(*) FILTER (WHERE humidity IS NULL),
    COUNT(*),
    ROUND(100.0 * COUNT(*) FILTER (WHERE humidity IS NULL) / COUNT(*), 2)
FROM sensor_data
UNION ALL
SELECT 
    'vdd',
    COUNT(*) FILTER (WHERE vdd IS NULL),
    COUNT(*),
    ROUND(100.0 * COUNT(*) FILTER (WHERE vdd IS NULL) / COUNT(*), 2)
FROM sensor_data;

-- Readings per day
SELECT 
    time::date as day,
    COUNT(*) as readings,
    COUNT(DISTINCT device_name) as active_devices
FROM sensor_data
GROUP BY day
ORDER BY day DESC
LIMIT 30;

-- Gaps in data (days with no readings)
WITH date_range AS (
    SELECT generate_series(
        (SELECT MIN(time)::date FROM sensor_data),
        (SELECT MAX(time)::date FROM sensor_data),
        '1 day'::interval
    )::date as day
),
daily_counts AS (
    SELECT 
        time::date as day,
        COUNT(*) as readings
    FROM sensor_data
    GROUP BY time::date
)
SELECT 
    dr.day,
    COALESCE(dc.readings, 0) as readings
FROM date_range dr
LEFT JOIN daily_counts dc ON dr.day = dc.day
WHERE COALESCE(dc.readings, 0) < 100
ORDER BY dr.day DESC
LIMIT 30;


-- ============================================
-- HYPERTABLE MANAGEMENT
-- ============================================

-- View hypertable information
SELECT * FROM timescaledb_information.hypertables;

-- View chunks (data partitions)
SELECT 
    chunk_name,
    range_start::date,
    range_end::date,
    pg_size_pretty(total_bytes) as size,
    pg_size_pretty(compressed_total_size) as compressed_size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sensor_data'
ORDER BY range_start DESC
LIMIT 20;

-- Compression statistics
SELECT 
    chunk_name,
    pg_size_pretty(before_compression_total_bytes) as uncompressed,
    pg_size_pretty(after_compression_total_bytes) as compressed,
    ROUND(100 - (after_compression_total_bytes::float / 
        before_compression_total_bytes::float * 100), 2) as compression_ratio_percent
FROM timescaledb_information.compressed_chunk_stats
ORDER BY chunk_name DESC
LIMIT 10;

-- View continuous aggregate refresh status
SELECT * FROM timescaledb_information.continuous_aggregates;


-- ============================================
-- EXPORT QUERIES
-- ============================================

-- Export to CSV (run in psql with \copy)
-- \copy (SELECT time, device_name, dev_place, temperature, humidity FROM sensor_data WHERE time > '2021-06-01') TO '/tmp/sensor_export.csv' CSV HEADER

-- Export daily averages
-- \copy (SELECT time_bucket('1 day', time) AS day, dev_place, AVG(temperature) as avg_temp, AVG(humidity) as avg_humidity FROM sensor_data GROUP BY day, dev_place ORDER BY day) TO '/tmp/daily_averages.csv' CSV HEADER


-- ============================================
-- USEFUL VIEWS (Create these for convenience)
-- ============================================

-- Daily summary view
CREATE OR REPLACE VIEW daily_summary AS
SELECT 
    time_bucket('1 day', time) AS day,
    device_name,
    dev_place,
    COUNT(*) as reading_count,
    ROUND(AVG(temperature)::numeric, 2) as avg_temp,
    ROUND(MIN(temperature)::numeric, 2) as min_temp,
    ROUND(MAX(temperature)::numeric, 2) as max_temp,
    ROUND(AVG(humidity)::numeric, 1) as avg_humidity,
    AVG(vdd)::integer as avg_battery_mv
FROM sensor_data
GROUP BY day, device_name, dev_place;

-- Query the daily summary
-- SELECT * FROM daily_summary ORDER BY day DESC LIMIT 50;
