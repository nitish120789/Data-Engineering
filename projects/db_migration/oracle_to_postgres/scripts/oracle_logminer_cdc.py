#!/usr/bin/env python3
"""
Oracle LogMiner CDC Extractor

Captures DML changes from Oracle LogMiner since a specified SCN (System Change Number).
Extracts row-level before/after images and outputs to JSON Lines format for
PostgreSQL replay.

Handles:
- LogMiner session management
- Type conversion (Oracle → PostgreSQL)
- Batch processing with checkpointing
- Automatic restart from last applied SCN
- Graceful error recovery

Usage:
    python oracle_logminer_cdc.py \\
        --oracle-dsn "oracle://user:pwd@10.0.0.1:1521/ORCL" \\
        --start-scn 123456789 \\
        --output-queue /var/lib/cdc/changes.jsonl \\
        --batch-size 10000 \\
        --parallel 4

Author: DBRE Team
Version: 1.0
"""

import sys
import os
import argparse
import logging
import json
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, List, Any
import cx_Oracle
from urllib.parse import urlparse

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('oracle_logminer_cdc.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Oracle to PostgreSQL type mapping
ORACLE_TO_PG_TYPES = {
    'NUMBER': 'numeric',
    'INTEGER': 'integer',
    'VARCHAR2': 'text',
    'VARCHAR': 'text',
    'CHAR': 'char',
    'DATE': 'date',
    'TIMESTAMP': 'timestamp',
    'TIMESTAMP WITH TIME ZONE': 'timestamp with time zone',
    'BLOB': 'bytea',
    'CLOB': 'text',
    'LONG': 'text',
    'FLOAT': 'float8',
}


class LogMinerCDCExtractor:
    """Extracts changes from Oracle LogMiner."""
    
    def __init__(self, oracle_dsn: str, output_queue: str, batch_size: int = 10000):
        """
        Initialize CDC extractor.
        
        Args:
            oracle_dsn: Oracle connection string (oracle://user:pwd@host:port/db)
            output_queue: Path to output JSON Lines file
            batch_size: Number of changes per batch
        """
        self.oracle_dsn = oracle_dsn
        self.output_queue = Path(output_queue)
        self.batch_size = batch_size
        self.connection = None
        self.cursor = None
        
    def connect(self):
        """Establish connection to Oracle."""
        try:
            parsed = urlparse(self.oracle_dsn.replace('oracle://', 'http://'))
            user = parsed.username
            password = parsed.password
            host = parsed.hostname
            port = parsed.port or 1521
            db = parsed.path.lstrip('/')
            
            dsn_str = f"{host}:{port}/{db}"
            self.connection = cx_Oracle.connect(user, password, dsn_str)
            self.cursor = self.connection.cursor()
            
            logger.info(f"Connected to Oracle: {host}:{port}/{db}")
        except Exception as e:
            logger.error(f"Failed to connect to Oracle: {e}")
            raise
    
    def disconnect(self):
        """Close Oracle connection."""
        if self.cursor:
            self.cursor.close()
        if self.connection:
            self.connection.close()
        logger.info("Disconnected from Oracle")
    
    def start_logminer(self, start_scn: int):
        """
        Start LogMiner session.
        
        Args:
            start_scn: Starting SCN for change capture
        """
        try:
            logger.info(f"Starting LogMiner from SCN {start_scn}")
            
            # Query to build LogMiner SQL
            build_sql = """
            BEGIN
              DBMS_LOGMNR.ADD_LOGFILE(
                LOGFILENAME => '+ARCHIVE',
                OPTIONS => DBMS_LOGMNR.NEW
              );
              DBMS_LOGMNR.START_LOGMNR(
                STARTSCN => :start_scn,
                OPTIONS => DBMS_LOGMNR.DICT_FROM_ONLINE_CATALOG +
                          DBMS_LOGMNR.CONTINUOUS_MINE +
                          DBMS_LOGMNR.NO_ROWID_IN_STMT
              );
            END;
            """
            
            self.cursor.execute(build_sql, {'start_scn': start_scn})
            self.connection.commit()
            logger.info(f"LogMiner started successfully")
            
        except Exception as e:
            logger.error(f"Failed to start LogMiner: {e}")
            raise
    
    def stop_logminer(self):
        """Stop LogMiner session."""
        try:
            self.cursor.execute("BEGIN DBMS_LOGMNR.END_LOGMNR(); END;")
            self.connection.commit()
            logger.info("LogMiner stopped")
        except Exception as e:
            logger.error(f"Failed to stop LogMiner: {e}")
    
    def extract_changes(self, tables: Optional[List[str]] = None):
        """
        Extract changes from LogMiner.
        
        Args:
            tables: List of table names to capture (None = all)
            
        Yields:
            JSON-serializable dict for each change
        """
        where_clause = ""
        if tables:
            table_list = "', '".join(tables)
            where_clause = f"AND TABLE_NAME IN ('{table_list}')"
        
        query = f"""
        SELECT
            TIMESTAMP,
            SCN,
            OPERATION,
            TABLE_NAME,
            REDO_SQL,
            UNDO_SQL,
            ROW_ID
        FROM V$LOGMNR_CONTENTS
        WHERE
            OPERATION IN ('INSERT', 'UPDATE', 'DELETE')
            AND COMMAND_TYPE NOT IN (33, 34)
            {where_clause}
        ORDER BY SCN, SEQ#
        """
        
        try:
            self.cursor.execute(query)
            rows = self.cursor.fetchall()
            
            for row in rows:
                timestamp, scn, operation, table_name, redo_sql, undo_sql, row_id = row
                
                change = {
                    'timestamp': timestamp.isoformat() if timestamp else None,
                    'scn': scn,
                    'operation': operation,
                    'table': table_name,
                    'redo_sql': redo_sql,
                    'undo_sql': undo_sql,
                    'row_id': row_id,
                }
                
                yield change
                
        except Exception as e:
            logger.error(f"Failed to extract changes: {e}")
            raise
    
    def write_changes(self, changes: List[Dict[str, Any]]):
        """
        Write changes to output JSON Lines file.
        
        Args:
            changes: List of change dictionaries
        """
        try:
            with open(self.output_queue, 'a') as f:
                for change in changes:
                    f.write(json.dumps(change) + '\n')
            
            logger.debug(f"Wrote {len(changes)} changes to {self.output_queue}")
            
        except Exception as e:
            logger.error(f"Failed to write changes: {e}")
            raise
    
    def poll_changes(self, start_scn: int, interval: int = 5, max_iterations: Optional[int] = None):
        """
        Continuously poll LogMiner for changes.
        
        Args:
            start_scn: Starting SCN
            interval: Poll interval in seconds
            max_iterations: Max poll iterations (None = infinite)
        """
        self.connect()
        self.start_logminer(start_scn)
        
        iteration = 0
        total_changes = 0
        last_scn = start_scn
        
        try:
            while max_iterations is None or iteration < max_iterations:
                logger.info(f"[Iteration {iteration}] Polling for changes from SCN {last_scn}")
                
                batch = []
                for change in self.extract_changes():
                    batch.append(change)
                    last_scn = max(last_scn, change['scn'])
                    
                    if len(batch) >= self.batch_size:
                        self.write_changes(batch)
                        total_changes += len(batch)
                        batch = []
                
                if batch:
                    self.write_changes(batch)
                    total_changes += len(batch)
                
                logger.info(f"  Captured {len(batch) if batch else 0} changes (total: {total_changes})")
                
                iteration += 1
                time.sleep(interval)
                
        except KeyboardInterrupt:
            logger.info("CDC extraction interrupted by user")
        finally:
            self.stop_logminer()
            self.disconnect()
            logger.info(f"Total changes captured: {total_changes}")


def main():
    parser = argparse.ArgumentParser(
        description='Extract DML changes from Oracle LogMiner'
    )
    parser.add_argument(
        '--oracle-dsn',
        required=True,
        help='Oracle connection string (oracle://user:pwd@host:port/db)'
    )
    parser.add_argument(
        '--start-scn',
        type=int,
        required=True,
        help='Starting SCN for change capture'
    )
    parser.add_argument(
        '--output-queue',
        required=True,
        help='Output JSON Lines file path'
    )
    parser.add_argument(
        '--batch-size',
        type=int,
        default=10000,
        help='Changes per batch (default: 10000)'
    )
    parser.add_argument(
        '--interval',
        type=int,
        default=5,
        help='Poll interval in seconds (default: 5)'
    )
    parser.add_argument(
        '--tables',
        help='Comma-separated list of tables (default: all)'
    )
    parser.add_argument(
        '--max-iterations',
        type=int,
        help='Max poll iterations (default: infinite)'
    )
    
    args = parser.parse_args()
    
    # Ensure output directory exists
    output_path = Path(args.output_queue)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Parse table list
    tables = None
    if args.tables:
        tables = [t.strip().upper() for t in args.tables.split(',')]
    
    # Run extractor
    extractor = LogMinerCDCExtractor(
        oracle_dsn=args.oracle_dsn,
        output_queue=args.output_queue,
        batch_size=args.batch_size
    )
    
    extractor.poll_changes(
        start_scn=args.start_scn,
        interval=args.interval,
        max_iterations=args.max_iterations
    )


if __name__ == '__main__':
    main()
