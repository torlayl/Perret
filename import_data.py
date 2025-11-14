#!/usr/bin/env python3
"""
Import Tour Perret sensor data from JSON log file into TimescaleDB.

This script reads the large JSON log file line by line (each line is a separate JSON object),
parses the sensor data, and efficiently inserts it into a TimescaleDB hypertable using batch inserts.
"""

import json
import sys
from datetime import datetime
from typing import Dict, Any, Optional
import psycopg2
from psycopg2.extras import execute_batch
from psycopg2 import sql
import argparse
from pathlib import Path


class SensorDataImporter:
    def __init__(self, db_config: Dict[str, str], batch_size: int = 1000):
        """
        Initialize the importer.
        
        Args:
            db_config: Database connection configuration
            batch_size: Number of records to insert in one batch
        """
        self.db_config = db_config
        self.batch_size = batch_size
        self.conn = None
        self.cursor = None
        
    def connect(self):
        """Establish database connection."""
        try:
            self.conn = psycopg2.connect(**self.db_config)
            self.cursor = self.conn.cursor()
            print(f"✓ Connected to database: {self.db_config['dbname']}")
        except Exception as e:
            print(f"✗ Failed to connect to database: {e}")
            sys.exit(1)
    
    def close(self):
        """Close database connection."""
        if self.cursor:
            self.cursor.close()
        if self.conn:
            self.conn.close()
            print("✓ Database connection closed")
    
    def parse_sensor_record(self, line: str) -> Optional[tuple]:
        """
        Parse a JSON line from the log file and extract sensor data.
        
        Args:
            line: JSON string from log file
            
        Returns:
            Tuple of values for database insertion, or None if parsing fails
        """
        try:
            data = json.loads(line.strip())
            
            # Parse timestamp
            timestamp = data.get('_date')
            if not timestamp:
                timestamp = datetime.fromtimestamp(data.get('_timestamp', 0) / 1000).isoformat()
            
            # Device location
            dev_location = data.get('_devLocation', {})
            
            # Gateway info (use first gateway if multiple)
            rx_info = data.get('rxInfo', [{}])[0]
            gateway_location = rx_info.get('location', {})
            
            # Transmission info
            tx_info = data.get('txInfo', {})
            
            # Sensor readings from object field
            sensor_obj = data.get('object', {})
            
            return (
                timestamp,  # time
                data.get('applicationName'),
                data.get('deviceName'),
                data.get('devEUI'),
                dev_location.get('latitude'),
                dev_location.get('longitude'),
                dev_location.get('altitude'),
                dev_location.get('place'),
                
                # Gateway info
                rx_info.get('gatewayID'),
                gateway_location.get('latitude'),
                gateway_location.get('longitude'),
                gateway_location.get('altitude'),
                rx_info.get('rssi'),
                rx_info.get('loRaSNR'),
                
                # Transmission
                tx_info.get('frequency'),
                tx_info.get('dr'),
                data.get('adr'),
                data.get('fCnt'),
                data.get('fPort'),
                
                # Sensor readings
                sensor_obj.get('temperature'),
                sensor_obj.get('humidity'),
                sensor_obj.get('dewpoint'),
                sensor_obj.get('vdd'),
                sensor_obj.get('accMotion'),
                sensor_obj.get('digital'),
                sensor_obj.get('waterleak'),
                sensor_obj.get('pulseAbs'),
                sensor_obj.get('x'),
                sensor_obj.get('y'),
                sensor_obj.get('z'),
                
                # Metadata
                data.get('_redundancy'),
                data.get('_topic'),
                
                # Raw data
                data.get('data'),
                json.dumps(sensor_obj)  # Store object as JSONB
            )
        except json.JSONDecodeError as e:
            print(f"⚠ Warning: Failed to parse JSON: {e}")
            return None
        except Exception as e:
            print(f"⚠ Warning: Error processing record: {e}")
            return None
    
    def import_data(self, log_file_path: Path, skip_errors: bool = True):
        """
        Import data from log file into database.
        
        Args:
            log_file_path: Path to the JSON log file
            skip_errors: Continue on errors if True
        """
        if not log_file_path.exists():
            print(f"✗ Error: File not found: {log_file_path}")
            sys.exit(1)
        
        insert_query = """
            INSERT INTO sensor_data (
                time, application_name, device_name, dev_eui,
                dev_latitude, dev_longitude, dev_altitude, dev_place,
                gateway_id, gateway_latitude, gateway_longitude, gateway_altitude,
                rssi, lora_snr,
                frequency, data_rate, adr, frame_counter, f_port,
                temperature, humidity, dewpoint, vdd,
                acc_motion, digital, waterleak, pulse_abs,
                x, y, z,
                redundancy, topic,
                raw_data, raw_object
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                %s, %s, %s, %s
            )
        """
        
        batch = []
        total_lines = 0
        imported_lines = 0
        error_count = 0
        
        print(f"\n📖 Reading file: {log_file_path}")
        print(f"📦 Batch size: {self.batch_size}")
        print(f"⚙️  Processing...\n")
        
        try:
            with open(log_file_path, 'r', encoding='utf-8') as f:
                for line_num, line in enumerate(f, 1):
                    total_lines += 1
                    
                    if line.strip():
                        record = self.parse_sensor_record(line)
                        if record:
                            batch.append(record)
                            imported_lines += 1
                        else:
                            error_count += 1
                    
                    # Insert batch when it reaches batch_size
                    if len(batch) >= self.batch_size:
                        try:
                            execute_batch(self.cursor, insert_query, batch, page_size=self.batch_size)
                            self.conn.commit()
                            print(f"  ✓ Inserted batch: {imported_lines:,} records imported so far...")
                            batch = []
                        except Exception as e:
                            print(f"  ✗ Error inserting batch: {e}")
                            self.conn.rollback()
                            if not skip_errors:
                                raise
                            batch = []
                    
                    # Progress indicator every 10,000 lines
                    if line_num % 10000 == 0:
                        print(f"  📊 Processed {line_num:,} lines ({imported_lines:,} imported, {error_count:,} errors)")
                
                # Insert remaining records
                if batch:
                    try:
                        execute_batch(self.cursor, insert_query, batch, page_size=len(batch))
                        self.conn.commit()
                        print(f"  ✓ Inserted final batch: {imported_lines:,} records")
                    except Exception as e:
                        print(f"  ✗ Error inserting final batch: {e}")
                        self.conn.rollback()
                        if not skip_errors:
                            raise
            
            print(f"\n" + "="*60)
            print(f"📊 Import Summary:")
            print(f"  Total lines processed: {total_lines:,}")
            print(f"  Successfully imported: {imported_lines:,}")
            print(f"  Errors encountered:   {error_count:,}")
            print(f"  Success rate:         {(imported_lines/total_lines*100):.2f}%")
            print("="*60)
            
            # Display some statistics
            self.show_statistics()
            
        except KeyboardInterrupt:
            print("\n\n⚠ Import interrupted by user")
            self.conn.rollback()
            sys.exit(1)
        except Exception as e:
            print(f"\n✗ Fatal error during import: {e}")
            self.conn.rollback()
            raise
    
    def show_statistics(self):
        """Display database statistics after import."""
        print("\n📈 Database Statistics:")
        
        queries = [
            ("Total records", "SELECT COUNT(*) FROM sensor_data"),
            ("Date range", """
                SELECT 
                    MIN(time)::date as earliest, 
                    MAX(time)::date as latest,
                    MAX(time)::date - MIN(time)::date as days
                FROM sensor_data
            """),
            ("Unique devices", "SELECT COUNT(DISTINCT device_name) FROM sensor_data"),
            ("Unique locations", "SELECT COUNT(DISTINCT dev_place) FROM sensor_data"),
            ("Records per device", """
                SELECT device_name, dev_place, COUNT(*) as records
                FROM sensor_data 
                GROUP BY device_name, dev_place 
                ORDER BY records DESC
            """),
        ]
        
        for title, query in queries:
            try:
                self.cursor.execute(query)
                result = self.cursor.fetchall()
                print(f"\n  {title}:")
                for row in result:
                    print(f"    {row}")
            except Exception as e:
                print(f"  ⚠ Error getting {title}: {e}")


def main():
    parser = argparse.ArgumentParser(
        description='Import Tour Perret sensor data into TimescaleDB',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    
    parser.add_argument(
        '--file', '-f',
        type=Path,
        default=Path('./Data/tourperret.log'),
        help='Path to the JSON log file'
    )
    
    parser.add_argument(
        '--host',
        default='localhost',
        help='Database host'
    )
    
    parser.add_argument(
        '--port',
        type=int,
        default=5432,
        help='Database port'
    )
    
    parser.add_argument(
        '--dbname',
        default='tourperret',
        help='Database name'
    )
    
    parser.add_argument(
        '--user',
        default='postgres',
        help='Database user'
    )
    
    parser.add_argument(
        '--password',
        default='postgres',
        help='Database password'
    )
    
    parser.add_argument(
        '--batch-size',
        type=int,
        default=1000,
        help='Number of records per batch insert'
    )
    
    parser.add_argument(
        '--stop-on-error',
        action='store_true',
        help='Stop on first error (default: continue)'
    )
    
    args = parser.parse_args()
    
    # Database configuration
    db_config = {
        'host': args.host,
        'port': args.port,
        'dbname': args.dbname,
        'user': args.user,
        'password': args.password
    }
    
    print("="*60)
    print("Tour Perret Sensor Data Importer")
    print("="*60)
    
    # Create importer and run
    importer = SensorDataImporter(db_config, batch_size=args.batch_size)
    
    try:
        importer.connect()
        importer.import_data(args.file, skip_errors=not args.stop_on_error)
    except Exception as e:
        print(f"\n✗ Import failed: {e}")
        sys.exit(1)
    finally:
        importer.close()
    
    print("\n✓ Import completed successfully!")


if __name__ == '__main__':
    main()
