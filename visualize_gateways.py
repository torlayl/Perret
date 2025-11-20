#!/usr/bin/env python3
"""
Visualize Tour Perret Gateways on a Map
Displays all gateways and their geolocations using Folium
"""

import psycopg2
import folium
from folium import plugins
import os

# Database connection parameters
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'tourperret',
    'user': 'postgres',
    'password': 'postgres'
}

def get_gateways():
    """Retrieve all unique gateways with their coordinates from the database"""
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    query = """
        SELECT DISTINCT 
            gateway_id, 
            gateway_latitude, 
            gateway_longitude
        FROM sensor_data
        WHERE gateway_latitude IS NOT NULL 
          AND gateway_longitude IS NOT NULL
        ORDER BY gateway_id;
    """
    
    cur.execute(query)
    results = cur.fetchall()
    
    cur.close()
    conn.close()
    
    return results

def create_map(gateways):
    """Create an interactive map with all gateways"""
    
    # Calculate center of all gateways
    lats = [g[1] for g in gateways]
    lons = [g[2] for g in gateways]
    center_lat = sum(lats) / len(lats)
    center_lon = sum(lons) / len(lons)
    
    # Create base map
    m = folium.Map(
        location=[center_lat, center_lon],
        zoom_start=12,
        tiles='OpenStreetMap'
    )
    
    # Track unique gateway locations (some gateways might have multiple locations)
    gateway_locations = {}
    
    for gateway_id, lat, lon in gateways:
        location_key = f"{lat:.6f},{lon:.6f}"
        
        if location_key not in gateway_locations:
            gateway_locations[location_key] = []
        
        gateway_locations[location_key].append(gateway_id)
    
    # Add markers for each unique location
    for location_key, gateway_ids in gateway_locations.items():
        lat, lon = map(float, location_key.split(','))
        
        # Create popup text
        popup_text = f"<b>Location:</b> {lat:.6f}, {lon:.6f}<br>"
        popup_text += f"<b>Gateway(s):</b><br>"
        for gw_id in gateway_ids:
            popup_text += f"<small>{gw_id}</small><br>"
        
        # Add marker
        folium.Marker(
            location=[lat, lon],
            popup=folium.Popup(popup_text, max_width=300),
            tooltip=f"{len(gateway_ids)} gateway(s)",
            icon=folium.Icon(color='red', icon='signal', prefix='fa')
        ).add_to(m)
    
    # Add marker cluster for better visualization
    marker_cluster = plugins.MarkerCluster().add_to(m)
    
    for location_key, gateway_ids in gateway_locations.items():
        lat, lon = map(float, location_key.split(','))
        popup_text = f"<b>Location:</b> {lat:.6f}, {lon:.6f}<br>"
        popup_text += f"<b>{len(gateway_ids)} Gateway(s)</b>"
        
        folium.Marker(
            location=[lat, lon],
            popup=folium.Popup(popup_text, max_width=300),
            icon=folium.Icon(color='blue', icon='broadcast-tower', prefix='fa')
        ).add_to(marker_cluster)
    
    # Add fullscreen button
    plugins.Fullscreen().add_to(m)
    
    # Add layer control
    folium.LayerControl().add_to(m)
    
    return m

def main():
    print("Connecting to Tour Perret database...")
    
    try:
        gateways = get_gateways()
        print(f"Found {len(gateways)} gateway records")
        
        # Count unique locations
        unique_locations = set((g[1], g[2]) for g in gateways)
        print(f"Found {len(unique_locations)} unique gateway locations")
        
        # Count unique gateway IDs
        unique_gateways = set(g[0] for g in gateways)
        print(f"Found {len(unique_gateways)} unique gateway IDs")
        
        print("\nGateway details:")
        print("-" * 80)
        
        # Group by gateway ID
        gateway_dict = {}
        for gw_id, lat, lon in gateways:
            if gw_id not in gateway_dict:
                gateway_dict[gw_id] = []
            gateway_dict[gw_id].append((lat, lon))
        
        for gw_id in sorted(gateway_dict.keys()):
            locations = gateway_dict[gw_id]
            print(f"\nGateway: {gw_id}")
            if len(locations) > 1:
                print(f"  Multiple locations ({len(locations)}):")
                for lat, lon in locations:
                    print(f"    - {lat:.6f}, {lon:.6f}")
            else:
                lat, lon = locations[0]
                print(f"  Location: {lat:.6f}, {lon:.6f}")
        
        print("\n" + "=" * 80)
        print("Creating interactive map...")
        
        m = create_map(gateways)
        
        output_file = "gateway_map.html"
        m.save(output_file)
        
        print(f"\n✓ Map created successfully: {output_file}")
        print(f"  Open this file in your browser to view the map")
        print(f"  Absolute path: {os.path.abspath(output_file)}")
        
    except psycopg2.Error as e:
        print(f"Database error: {e}")
        return 1
    except Exception as e:
        print(f"Error: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main())
