#!/usr/bin/env python3
"""
SQL Server CDC extractor for Azure SQL Hyperscale migration.
Author: Nitish Anand Srivastava

USAGE:
    python sqlserver_cdc_extractor.py \\
        --source-conn "DRIVER={ODBC Driver 17 for SQL Server};Server=sql-source;Database=OrderDB;UID=user;PWD=pass" \\
        --capture-instance "dbo_orders" \\
        --from-lsn "00000029000000be0003" \\
        --to-lsn "00000029000000c00001" \\
        --out-file "cdc_batch_001.jsonl"

DEPENDENCIES:
    - pyodbc (pip install pyodbc)
    - ODBC Driver 17 for SQL Server (Windows/Linux) or msodbcsql (macOS)
    - SQL Server Network Connectivity (source database must be accessible)

PREREQUISITES:
    1. Source SQL Server database must have CDC enabled on the target tables
    2. CDC capture instance must exist (created via enable_cdc.sql script)
    3. LSN values (from_lsn, to_lsn) must be valid hex strings and in correct order
    4. ODBC connection string must have read permissions on cdc.* tables
"""

import argparse
import json
import logging
import sys
from datetime import datetime
from pathlib import Path

try:
    import pyodbc
except ImportError:
    print("ERROR: pyodbc not found. Install with: pip install pyodbc")
    sys.exit(1)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)


def validate_hex_string(value: str, field_name: str, expected_len: int = None) -> bytes:
    """Validate and convert hex string to bytes."""
    try:
        if len(value) % 2 != 0:
            raise ValueError(f'{field_name} must be even-length hex string')
        result = bytes.fromhex(value)
        if expected_len and len(result) != expected_len:
            raise ValueError(f'{field_name} must be {expected_len} bytes ({expected_len*2} hex chars)')
        return result
    except ValueError as e:
        logger.error(f'Invalid {field_name}: {e}')
        raise


def get_connection(conn_str: str):
    """Establish ODBC connection to SQL Server with error handling."""
    try:
        conn = pyodbc.connect(conn_str, autocommit=False, timeout=30)
        logger.info('Connected to SQL Server')
        return conn
    except pyodbc.DatabaseError as e:
        logger.error(f'Connection failed: {e}')
        raise


def validate_cdc_enabled(cursor, capture_instance: str):
    """Verify capture instance exists and is accessible."""
    try:
        # Try to query CDC metadata
        sql = f"SELECT cdc_instance = '{capture_instance}';"
        cursor.execute(sql)
        logger.info(f'Verified capture instance: {capture_instance}')
    except pyodbc.DatabaseError as e:
        logger.error(f'Capture instance validation failed: {e}')
        raise


def fetch_cdc_batch(cursor, capture_instance: str, from_lsn: bytes, to_lsn: bytes) -> tuple:
    """Fetch CDC changes within LSN range."""
    try:
        sql = f"""
        SELECT *
        FROM cdc.fn_cdc_get_all_changes_{capture_instance}(?, ?, 'all')
        ORDER BY __$start_lsn, __$seqval
        """
        cursor.execute(sql, from_lsn, to_lsn)
        rows = cursor.fetchall()
        columns = [c[0] for c in cursor.description]
        
        logger.info(f'Fetched {len(rows)} CDC records')
        return rows, columns
    except pyodbc.DatabaseError as e:
        logger.error(f'CDC fetch failed: {e}')
        raise


def to_json_records(rows, columns) -> list:
    """Convert CDC rows to JSON-serializable records."""
    payload = []
    for row_idx, row in enumerate(rows):
        try:
            item = {}
            for idx, col in enumerate(columns):
                val = row[idx]
                if isinstance(val, (bytes, bytearray)):
                    item[col] = val.hex()
                elif isinstance(val, datetime):
                    item[col] = val.isoformat()
                else:
                    item[col] = val
            payload.append(item)
        except Exception as e:
            logger.error(f'Row {row_idx} serialization failed: {e}')
            raise
    
    return payload


def main():
    parser = argparse.ArgumentParser(
        description='Extract SQL Server CDC changes to JSONL',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('--source-conn', required=True, 
                       help='ODBC connection string to source SQL Server')
    parser.add_argument('--capture-instance', required=True, 
                       help='CDC capture instance name (e.g., dbo_orders)')
    parser.add_argument('--from-lsn', required=True, 
                       help='Start LSN (hex string, e.g., 00000029000000be0003)')
    parser.add_argument('--to-lsn', required=True, 
                       help='End LSN (hex string, e.g., 00000029000000c00001)')
    parser.add_argument('--out-file', required=True, 
                       help='Output JSONL file path')
    args = parser.parse_args()

    try:
        # Validate LSN hex strings
        from_lsn = validate_hex_string(args.from_lsn, 'from_lsn', expected_len=10)
        to_lsn = validate_hex_string(args.to_lsn, 'to_lsn', expected_len=10)
        
        if from_lsn >= to_lsn:
            logger.error('from_lsn must be less than to_lsn')
            sys.exit(1)
        
        # Create output directory
        out_path = Path(args.out_file)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Connect and extract
        with get_connection(args.source_conn) as conn:
            cur = conn.cursor()
            validate_cdc_enabled(cur, args.capture_instance)
            rows, cols = fetch_cdc_batch(cur, args.capture_instance, from_lsn, to_lsn)
            records = to_json_records(rows, cols)
        
        # Write JSONL
        with out_path.open('w', encoding='utf-8') as f:
            for rec in records:
                f.write(json.dumps(rec, ensure_ascii=True) + '\n')
        
        logger.info(f'Extracted {len(records)} CDC records to {out_path}')
        
    except Exception as e:
        logger.error(f'CDC extraction failed: {e}')
        sys.exit(1)


if __name__ == '__main__':
    main()
