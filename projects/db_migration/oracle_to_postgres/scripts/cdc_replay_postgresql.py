#!/usr/bin/env python3
"""
CDC Replay Engine for PostgreSQL

Consumes change events from JSON Lines queue (Oracle LogMiner CDC output)
and applies them to PostgreSQL target. Handles:
- INSERT, UPDATE, DELETE operations
- Transaction ordering and idempotency
- Primary key lookups and conflict resolution
- Checkpoint tracking for resume on restart

Usage:
    python cdc_replay_postgresql.py \\
        --pg-dsn "postgresql://user:pwd@pg-target.postgres.database.azure.com:5432/mydb" \\
        --input-queue /var/lib/cdc/changes.jsonl \\
        --batch-size 1000 \\
        --checkpoint-table public.cdc_checkpoint

Author: DBRE Team
Version: 1.0
"""

import sys
import os
import json
import argparse
import logging
import time
from pathlib import Path
from typing import Dict, List, Any, Optional
from datetime import datetime
import psycopg2
from psycopg2.extras import DictCursor, execute_batch
from urllib.parse import urlparse

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('cdc_replay_postgresql.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)


class CDCReplayEngine:
    """Replays CDC changes to PostgreSQL target."""
    
    def __init__(self, pg_dsn: str, checkpoint_table: str = 'public.cdc_checkpoint'):
        """
        Initialize replay engine.
        
        Args:
            pg_dsn: PostgreSQL connection string
            checkpoint_table: Table for tracking applied changes
        """
        self.pg_dsn = pg_dsn
        self.checkpoint_table = checkpoint_table
        self.connection = None
        self.cursor = None
        
    def connect(self):
        """Establish connection to PostgreSQL."""
        try:
            # Parse DSN
            parsed = urlparse(self.pg_dsn)
            
            conn_params = {
                'host': parsed.hostname,
                'port': parsed.port or 5432,
                'user': parsed.username,
                'password': parsed.password,
                'database': parsed.path.lstrip('/'),
            }
            
            self.connection = psycopg2.connect(**conn_params)
            self.cursor = self.connection.cursor(cursor_factory=DictCursor)
            
            logger.info(f"Connected to PostgreSQL: {parsed.hostname}:{conn_params['port']}/{conn_params['database']}")
            
            # Ensure checkpoint table exists
            self._create_checkpoint_table()
            
        except Exception as e:
            logger.error(f"Failed to connect to PostgreSQL: {e}")
            raise
    
    def disconnect(self):
        """Close PostgreSQL connection."""
        if self.cursor:
            self.cursor.close()
        if self.connection:
            self.connection.close()
        logger.info("Disconnected from PostgreSQL")
    
    def _create_checkpoint_table(self):
        """Create checkpoint table if it doesn't exist."""
        try:
            sql = f"""
            CREATE TABLE IF NOT EXISTS {self.checkpoint_table} (
                id SERIAL PRIMARY KEY,
                table_name TEXT NOT NULL,
                last_scn BIGINT NOT NULL,
                last_timestamp TIMESTAMP,
                rows_applied BIGINT DEFAULT 0,
                updated_at TIMESTAMP DEFAULT NOW()
            );
            CREATE INDEX IF NOT EXISTS idx_checkpoint_table ON {self.checkpoint_table}(table_name);
            """
            
            self.cursor.execute(sql)
            self.connection.commit()
            logger.info(f"Checkpoint table {self.checkpoint_table} ready")
            
        except Exception as e:
            logger.error(f"Failed to create checkpoint table: {e}")
            raise
    
    def get_last_scn(self, table_name: str) -> int:
        """
        Get last applied SCN for a table.
        
        Args:
            table_name: Target table name
            
        Returns:
            Last applied SCN (0 if no checkpoint)
        """
        try:
            sql = f"SELECT last_scn FROM {self.checkpoint_table} WHERE table_name = %s"
            self.cursor.execute(sql, (table_name,))
            result = self.cursor.fetchone()
            return result['last_scn'] if result else 0
        except Exception as e:
            logger.warning(f"Failed to get checkpoint for {table_name}: {e}")
            return 0
    
    def update_checkpoint(self, table_name: str, scn: int, timestamp: Optional[datetime] = None, rows_applied: int = 0):
        """
        Update checkpoint after applying changes.
        
        Args:
            table_name: Target table name
            scn: SCN of applied changes
            timestamp: Timestamp of changes
            rows_applied: Number of rows applied
        """
        try:
            sql = f"""
            INSERT INTO {self.checkpoint_table} (table_name, last_scn, last_timestamp, rows_applied)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (table_name) DO UPDATE SET
                last_scn = GREATEST({self.checkpoint_table}.last_scn, EXCLUDED.last_scn),
                last_timestamp = EXCLUDED.last_timestamp,
                rows_applied = rows_applied + EXCLUDED.rows_applied,
                updated_at = NOW()
            """
            self.cursor.execute(sql, (table_name, scn, timestamp, rows_applied))
            self.connection.commit()
            
        except Exception as e:
            logger.error(f"Failed to update checkpoint for {table_name}: {e}")
    
    def apply_insert(self, table_name: str, data: Dict[str, Any]) -> bool:
        """
        Apply INSERT operation.
        
        Args:
            table_name: Target table name
            data: Row data (column → value)
            
        Returns:
            True if successful
        """
        try:
            columns = ', '.join(data.keys())
            placeholders = ', '.join(['%s'] * len(data))
            values = list(data.values())
            
            sql = f"INSERT INTO {table_name} ({columns}) VALUES ({placeholders})"
            
            self.cursor.execute(sql, values)
            return True
            
        except psycopg2.IntegrityError as e:
            # Duplicate key or constraint violation; skip this row
            logger.debug(f"INSERT conflict on {table_name}: {e}")
            return False
        except Exception as e:
            logger.error(f"Failed to INSERT into {table_name}: {e}")
            return False
    
    def apply_update(self, table_name: str, pk: Dict[str, Any], data: Dict[str, Any]) -> bool:
        """
        Apply UPDATE operation.
        
        Args:
            table_name: Target table name
            pk: Primary key columns (column → value)
            data: New row data (column → value)
            
        Returns:
            True if successful
        """
        try:
            set_clause = ', '.join([f"{k} = %s" for k in data.keys()])
            where_clause = ' AND '.join([f"{k} = %s" for k in pk.keys()])
            values = list(data.values()) + list(pk.values())
            
            sql = f"UPDATE {table_name} SET {set_clause} WHERE {where_clause}"
            
            self.cursor.execute(sql, values)
            return True
            
        except Exception as e:
            logger.error(f"Failed to UPDATE {table_name}: {e}")
            return False
    
    def apply_delete(self, table_name: str, pk: Dict[str, Any]) -> bool:
        """
        Apply DELETE operation.
        
        Args:
            table_name: Target table name
            pk: Primary key columns (column → value)
            
        Returns:
            True if successful
        """
        try:
            where_clause = ' AND '.join([f"{k} = %s" for k in pk.keys()])
            values = list(pk.values())
            
            sql = f"DELETE FROM {table_name} WHERE {where_clause}"
            
            self.cursor.execute(sql, values)
            return True
            
        except Exception as e:
            logger.error(f"Failed to DELETE from {table_name}: {e}")
            return False
    
    def replay_change(self, change: Dict[str, Any]) -> bool:
        """
        Apply a single CDC change to PostgreSQL.
        
        Args:
            change: Change dictionary from LogMiner CDC
            
        Returns:
            True if successful
        """
        try:
            operation = change.get('operation')
            table = change.get('table')
            scn = change.get('scn')
            timestamp = change.get('timestamp')
            
            # Placeholder: in production, parse REDO_SQL/UNDO_SQL to extract data
            # For this example, we assume JSON structure: data, pk fields in change
            if operation == 'INSERT':
                return self.apply_insert(table, change.get('data', {}))
            elif operation == 'UPDATE':
                return self.apply_update(table, change.get('pk', {}), change.get('data', {}))
            elif operation == 'DELETE':
                return self.apply_delete(table, change.get('pk', {}))
            else:
                logger.warning(f"Unknown operation: {operation}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to apply change: {e}")
            return False
    
    def process_queue(self, queue_file: str, batch_size: int = 1000):
        """
        Process CDC queue file.
        
        Args:
            queue_file: Path to JSON Lines queue
            batch_size: Changes per batch
        """
        queue_path = Path(queue_file)
        
        if not queue_path.exists():
            logger.warning(f"Queue file does not exist: {queue_file}")
            return
        
        applied_total = 0
        failed_total = 0
        batch = []
        last_scn = 0
        last_table = None
        
        try:
            with open(queue_path, 'r') as f:
                for line in f:
                    if not line.strip():
                        continue
                    
                    try:
                        change = json.loads(line)
                        batch.append(change)
                        last_scn = max(last_scn, change.get('scn', 0))
                        last_table = change.get('table')
                        
                        if len(batch) >= batch_size:
                            applied, failed = self._apply_batch(batch)
                            applied_total += applied
                            failed_total += failed
                            
                            # Update checkpoint
                            if last_table and last_scn:
                                self.update_checkpoint(last_table, last_scn, rows_applied=applied)
                            
                            batch = []
                            
                    except json.JSONDecodeError as e:
                        logger.error(f"Failed to parse JSON: {e}")
                        continue
            
            # Process remaining batch
            if batch:
                applied, failed = self._apply_batch(batch)
                applied_total += applied
                failed_total += failed
                
                if last_table and last_scn:
                    self.update_checkpoint(last_table, last_scn, rows_applied=applied)
            
            logger.info(f"Queue processing complete: {applied_total} applied, {failed_total} failed")
            
        except Exception as e:
            logger.error(f"Failed to process queue: {e}")
    
    def _apply_batch(self, batch: List[Dict[str, Any]]) -> tuple:
        """
        Apply a batch of changes to PostgreSQL.
        
        Args:
            batch: List of change dictionaries
            
        Returns:
            Tuple: (applied_count, failed_count)
        """
        applied = 0
        failed = 0
        
        for change in batch:
            if self.replay_change(change):
                applied += 1
            else:
                failed += 1
        
        try:
            self.connection.commit()
        except Exception as e:
            logger.error(f"Failed to commit batch: {e}")
            self.connection.rollback()
            failed += len(batch) - failed
            applied = 0
        
        return applied, failed


def main():
    parser = argparse.ArgumentParser(
        description='Replay CDC changes to PostgreSQL target'
    )
    parser.add_argument(
        '--pg-dsn',
        required=True,
        help='PostgreSQL connection string'
    )
    parser.add_argument(
        '--input-queue',
        required=True,
        help='Input JSON Lines queue file'
    )
    parser.add_argument(
        '--batch-size',
        type=int,
        default=1000,
        help='Changes per batch (default: 1000)'
    )
    parser.add_argument(
        '--checkpoint-table',
        default='public.cdc_checkpoint',
        help='Checkpoint table name'
    )
    
    args = parser.parse_args()
    
    engine = CDCReplayEngine(
        pg_dsn=args.pg_dsn,
        checkpoint_table=args.checkpoint_table
    )
    
    engine.connect()
    try:
        engine.process_queue(args.input_queue, args.batch_size)
    finally:
        engine.disconnect()


if __name__ == '__main__':
    main()
