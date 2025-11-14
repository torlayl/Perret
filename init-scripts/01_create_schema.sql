-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Create the main sensor data table
CREATE TABLE IF NOT EXISTS sensor_data (
    time TIMESTAMPTZ NOT NULL,
    application_name TEXT,
    device_name TEXT,
    dev_eui TEXT,
    dev_latitude DOUBLE PRECISION,
    dev_longitude DOUBLE PRECISION,
    dev_altitude DOUBLE PRECISION,
    dev_place TEXT,
    
    -- Gateway information (first gateway)
    gateway_id TEXT,
    gateway_latitude DOUBLE PRECISION,
    gateway_longitude DOUBLE PRECISION,
    gateway_altitude DOUBLE PRECISION,
    rssi INTEGER,
    lora_snr DOUBLE PRECISION,
    
    -- Transmission info
    frequency BIGINT,
    data_rate INTEGER,
    adr BOOLEAN,
    frame_counter INTEGER,
    f_port INTEGER,
    
    -- Sensor readings (ELSYS EMS data)
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    dewpoint DOUBLE PRECISION,
    vdd INTEGER,  -- Battery voltage
    acc_motion INTEGER,
    digital INTEGER,
    waterleak INTEGER,
    pulse_abs INTEGER,
    x INTEGER,
    y INTEGER,
    z INTEGER,
    
    -- Metadata
    redundancy INTEGER,
    topic TEXT,
    
    -- Raw data for reference
    raw_data TEXT,
    raw_object JSONB
);

-- Create hypertable with 1-day chunks
-- This optimizes for time-series queries and data management
SELECT create_hypertable('sensor_data', 'time', 
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE
);

-- Create indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_sensor_device_name ON sensor_data (device_name, time DESC);
CREATE INDEX IF NOT EXISTS idx_sensor_dev_eui ON sensor_data (dev_eui, time DESC);
CREATE INDEX IF NOT EXISTS idx_sensor_place ON sensor_data (dev_place, time DESC);
CREATE INDEX IF NOT EXISTS idx_sensor_gateway ON sensor_data (gateway_id, time DESC);

-- Create index on JSONB data for flexible queries
CREATE INDEX IF NOT EXISTS idx_sensor_raw_object ON sensor_data USING GIN (raw_object);

-- Enable compression after 7 days (optional, for long-term storage efficiency)
ALTER TABLE sensor_data SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_name',
    timescaledb.compress_orderby = 'time DESC'
);

-- Add compression policy (compress data older than 7 days)
SELECT add_compression_policy('sensor_data', INTERVAL '7 days', if_not_exists => TRUE);

-- Create continuous aggregate for hourly statistics
CREATE MATERIALIZED VIEW IF NOT EXISTS sensor_data_hourly
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 hour', time) AS hour,
    device_name,
    dev_place,
    AVG(temperature) as avg_temperature,
    MIN(temperature) as min_temperature,
    MAX(temperature) as max_temperature,
    AVG(humidity) as avg_humidity,
    MIN(humidity) as min_humidity,
    MAX(humidity) as max_humidity,
    AVG(vdd) as avg_battery,
    COUNT(*) as reading_count
FROM sensor_data
GROUP BY hour, device_name, dev_place;

-- Add refresh policy for continuous aggregate
SELECT add_continuous_aggregate_policy('sensor_data_hourly',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE
);

-- Create a view for latest readings per device
CREATE OR REPLACE VIEW latest_sensor_readings AS
SELECT DISTINCT ON (device_name)
    device_name,
    dev_place,
    time,
    temperature,
    humidity,
    dewpoint,
    vdd,
    rssi,
    lora_snr
FROM sensor_data
ORDER BY device_name, time DESC;

-- Grant permissions (if needed for specific users)
-- GRANT ALL PRIVILEGES ON sensor_data TO your_user;
-- GRANT ALL PRIVILEGES ON sensor_data_hourly TO your_user;

COMMENT ON TABLE sensor_data IS 'Time-series data from IoT sensors at Tour Perret';
COMMENT ON COLUMN sensor_data.time IS 'Timestamp of the sensor reading';
COMMENT ON COLUMN sensor_data.device_name IS 'Unique identifier for the device';
COMMENT ON COLUMN sensor_data.dev_place IS 'Physical location description of the sensor';
COMMENT ON COLUMN sensor_data.temperature IS 'Temperature in Celsius';
COMMENT ON COLUMN sensor_data.humidity IS 'Relative humidity percentage';
COMMENT ON COLUMN sensor_data.vdd IS 'Battery voltage in millivolts';
