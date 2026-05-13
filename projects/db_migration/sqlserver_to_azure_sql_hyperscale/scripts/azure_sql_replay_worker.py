#!/usr/bin/env python3
"""
Replay worker to apply SQL Server CDC deltas into Azure SQL Hyperscale.
Author: Nitish Anand Srivastava
"""

import argparse
import json
import logging
from datetime import datetime
from pathlib import Path

import pyodbc

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s'
)


def connect(conn_str: str):
    return pyodbc.connect(conn_str, autocommit=False)


def ensure_checkpoint_table(cursor):
    cursor.execute(
        """
        IF OBJECT_ID('dbo.cdc_checkpoint', 'U') IS NULL
        BEGIN
            CREATE TABLE dbo.cdc_checkpoint (
                table_name NVARCHAR(256) NOT NULL PRIMARY KEY,
                last_lsn VARBINARY(10) NOT NULL,
                last_applied_at DATETIME2 NOT NULL,
                rows_applied BIGINT NOT NULL DEFAULT 0
            );
        END
        """
    )


def parse_operation(op_code: int):
    # SQL Server CDC operation codes:
    # 1 = delete, 2 = insert, 3 = update (before), 4 = update (after)
    if op_code == 1:
        return 'DELETE'
    if op_code == 2:
        return 'INSERT'
    if op_code == 3:
        return 'UPDATE_BEFORE'
    if op_code == 4:
        return 'UPDATE_AFTER'
    return 'SKIP'


def apply_record(cursor, table_name: str, record: dict, pk_col: str, last_record: dict = None):
    """
    Apply CDC record to Azure SQL. For UPDATE operations, merge pre/post records.
    
    Args:
        cursor: Database cursor
        table_name: Target table name
        record: Current CDC record (dict)
        pk_col: Primary key column name
        last_record: Previous record (for merging UPDATE before/after)
    
    Returns:
        Tuple of (records_applied, is_update_pending) where is_update_pending indicates
        if we need to wait for the UPDATE_AFTER record
    """
    op = parse_operation(record.get('__$operation', 0))
    
    if op == 'SKIP':
        return 0, False

    pk_val = record.get(pk_col)
    if pk_val is None:
        return 0, False

    data_cols = [k for k in record.keys() if not k.startswith('__$')]

    if op == 'DELETE':
        sql = f"DELETE FROM dbo.{table_name} WHERE {pk_col} = ?"
        cursor.execute(sql, pk_val)
        logging.info('Applied DELETE for %s.%s where %s=%s', table_name, table_name, pk_col, pk_val)
        return 1, False

    if op == 'INSERT':
        cols = ', '.join(data_cols)
        vals = ', '.join(['?'] * len(data_cols))
        sql = f"INSERT INTO dbo.{table_name} ({cols}) VALUES ({vals})"
        cursor.execute(sql, *[record[c] for c in data_cols])
        logging.info('Applied INSERT for %s where %s=%s', table_name, pk_col, pk_val)
        return 1, False

    if op == 'UPDATE_BEFORE':
        # Return 0 applied; wait for UPDATE_AFTER
        return 0, True

    if op == 'UPDATE_AFTER':
        # Apply the UPDATE using the post-image (current record)
        set_cols = [c for c in data_cols if c != pk_col]
        if not set_cols:
            logging.warning('UPDATE_AFTER has no updatable columns for %s.%s (PK only)', table_name, pk_col)
            return 0, False
        
        set_clause = ', '.join([f"{c} = ?" for c in set_cols])
        sql = f"UPDATE dbo.{table_name} SET {set_clause} WHERE {pk_col} = ?"
        params = [record[c] for c in set_cols] + [pk_val]
        cursor.execute(sql, *params)
        logging.info('Applied UPDATE for %s where %s=%s (%d columns)', table_name, pk_col, pk_val, len(set_cols))
        return 1, False

    return 0, False


def update_checkpoint(cursor, table_name: str, last_lsn_hex: str, rows_applied: int):
    last_lsn = bytes.fromhex(last_lsn_hex)
    cursor.execute(
        """
        MERGE dbo.cdc_checkpoint AS target
        USING (SELECT ? AS table_name, ? AS last_lsn, SYSUTCDATETIME() AS applied_at, ? AS rows_applied) AS src
        ON target.table_name = src.table_name
        WHEN MATCHED THEN
            UPDATE SET
                target.last_lsn = src.last_lsn,
                target.last_applied_at = src.applied_at,
                target.rows_applied = target.rows_applied + src.rows_applied
        WHEN NOT MATCHED THEN
            INSERT (table_name, last_lsn, last_applied_at, rows_applied)
            VALUES (src.table_name, src.last_lsn, src.applied_at, src.rows_applied);
        """,
        table_name,
        last_lsn,
        rows_applied
    )


def main():
    parser = argparse.ArgumentParser(description='Replay JSONL CDC records to Azure SQL')
    parser.add_argument('--target-conn', required=True, help='ODBC connection string for Azure SQL')
    parser.add_argument('--table-name', required=True, help='Target table name in dbo schema')
    parser.add_argument('--pk-col', required=True, help='Primary key column name')
    parser.add_argument('--in-file', required=True, help='Input JSONL file')
    parser.add_argument('--last-lsn', required=True, help='Last LSN (hex) represented by this batch')
    parser.add_argument('--batch-size', type=int, default=1000, help='Commit batch size (default: 1000)')
    args = parser.parse_args()

    input_path = Path(args.in_file)
    if not input_path.exists():
        raise FileNotFoundError(f'Input file not found: {input_path}')

    applied = 0
    batch_count = 0
    update_before_pending = False

    try:
        with connect(args.target_conn) as conn:
            cursor = conn.cursor()
            ensure_checkpoint_table(cursor)

            with input_path.open('r', encoding='utf-8') as f:
                for line in f:
                    if not line.strip():
                        continue
                    
                    try:
                        rec = json.loads(line)
                    except json.JSONDecodeError as e:
                        logging.error('Invalid JSON in input file: %s', str(e))
                        continue
                    
                    records_applied, is_update_pending = apply_record(cursor, args.table_name, rec, args.pk_col)
                    applied += records_applied
                    update_before_pending = is_update_pending
                    batch_count += 1

                    # Commit in batches
                    if batch_count % args.batch_size == 0:
                        try:
                            update_checkpoint(cursor, args.table_name, args.last_lsn, applied)
                            conn.commit()
                            logging.info('Committed batch %d (%d total rows applied)', batch_count // args.batch_size, applied)
                        except Exception as e:
                            conn.rollback()
                            logging.error('Batch commit failed: %s. Rolling back.', str(e))
                            raise

            # Final commit
            try:
                update_checkpoint(cursor, args.table_name, args.last_lsn, applied)
                conn.commit()
                logging.info('Final commit succeeded. Total %d records applied.', applied)
            except Exception as e:
                conn.rollback()
                logging.error('Final commit failed: %s', str(e))
                raise

    except Exception as e:
        logging.error('Replay worker failed: %s', str(e))
        raise

    logging.info('Applied %d records into dbo.%s (%d processed)', applied, args.table_name, batch_count)


if __name__ == '__main__':
    main()
