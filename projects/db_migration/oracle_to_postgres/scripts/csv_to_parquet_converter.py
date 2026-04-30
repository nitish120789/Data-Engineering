#!/usr/bin/env python3
"""
CSV to Parquet Converter for Azure Data Box Staged Data

Converts Oracle-exported CSV files to Parquet format for efficient
ingestion via Azure Data Factory (ADF). Handles type inference,
schema mapping, and parallel processing.

Usage:
    python csv_to_parquet_converter.py \\
        --input-dir /mnt/databox/csv_exports \\
        --output-dir /mnt/adls/parquet_staging \\
        --compression snappy \\
        --parallel 8

Author: DBRE Team
Version: 1.0
"""

import os
import sys
import argparse
import logging
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('csv_to_parquet_conversion.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Type mappings: Oracle CSV field types → PyArrow types
ORACLE_TO_ARROW_TYPES = {
    'NUMBER': pa.float64(),
    'INTEGER': pa.int64(),
    'VARCHAR2': pa.string(),
    'DATE': pa.date32(),
    'TIMESTAMP': pa.timestamp('ns'),
    'BLOB': pa.binary(),
    'CHAR': pa.string(),
    'CLOB': pa.string(),
    'LONG': pa.string(),
}


def infer_schema(csv_file, sample_rows=1000):
    """
    Infer Parquet schema from CSV sample rows.
    
    Args:
        csv_file: Path to CSV file
        sample_rows: Number of rows to sample for inference
        
    Returns:
        pyarrow.Schema object
    """
    try:
        # Read sample rows to infer types
        df = pd.read_csv(csv_file, nrows=sample_rows, low_memory=False)
        
        # Infer PyArrow schema
        table = pa.Table.from_pandas(df, preserve_index=False)
        schema = table.schema
        
        logger.info(f"Inferred schema for {csv_file.name}: {len(schema)} columns")
        return schema
    except Exception as e:
        logger.error(f"Failed to infer schema for {csv_file}: {e}")
        raise


def convert_csv_to_parquet(csv_file, output_dir, compression='snappy', chunk_size=50000):
    """
    Convert a single CSV file to Parquet format.
    
    Args:
        csv_file: Path to input CSV file
        output_dir: Output directory for Parquet files
        compression: Compression codec (snappy, gzip, brotli, none)
        chunk_size: Number of rows per Parquet chunk
        
    Returns:
        Tuple: (success: bool, rows_processed: int, output_path: Path)
    """
    try:
        table_name = csv_file.stem  # filename without extension
        output_path = Path(output_dir) / table_name
        output_path.mkdir(parents=True, exist_ok=True)
        
        logger.info(f"Converting {csv_file.name} to Parquet...")
        
        rows_processed = 0
        chunk_num = 0
        
        # Read CSV in chunks and write Parquet
        for chunk in pd.read_csv(csv_file, chunksize=chunk_size, low_memory=False):
            # Convert to PyArrow table
            table = pa.Table.from_pandas(chunk, preserve_index=False)
            
            # Write Parquet chunk
            chunk_file = output_path / f"part-{chunk_num:04d}.parquet"
            pq.write_table(table, str(chunk_file), compression=compression)
            
            rows_processed += len(chunk)
            chunk_num += 1
            
            if chunk_num % 10 == 0:
                logger.debug(f"  Processed {rows_processed} rows from {table_name}")
        
        logger.info(f"✓ {csv_file.name} → {table_name}/ ({rows_processed} rows, {chunk_num} chunks)")
        return (True, rows_processed, output_path)
        
    except Exception as e:
        logger.error(f"✗ Failed to convert {csv_file.name}: {e}")
        return (False, 0, None)


def main():
    parser = argparse.ArgumentParser(
        description='Convert Oracle CSV exports to Parquet format for ADF ingestion'
    )
    parser.add_argument(
        '--input-dir',
        required=True,
        help='Input directory containing CSV files from Data Box'
    )
    parser.add_argument(
        '--output-dir',
        required=True,
        help='Output directory for Parquet staging (ADLS path)'
    )
    parser.add_argument(
        '--compression',
        choices=['snappy', 'gzip', 'brotli', 'none'],
        default='snappy',
        help='Parquet compression codec (default: snappy)'
    )
    parser.add_argument(
        '--parallel',
        type=int,
        default=8,
        help='Number of parallel conversion jobs (default: 8)'
    )
    parser.add_argument(
        '--chunk-size',
        type=int,
        default=50000,
        help='Rows per Parquet chunk file (default: 50000)'
    )
    
    args = parser.parse_args()
    
    # Validate input/output directories
    input_dir = Path(args.input_dir)
    if not input_dir.exists():
        logger.error(f"Input directory does not exist: {input_dir}")
        sys.exit(1)
    
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Find all CSV files
    csv_files = list(input_dir.glob('*.csv'))
    if not csv_files:
        logger.warning(f"No CSV files found in {input_dir}")
        sys.exit(0)
    
    logger.info(f"Found {len(csv_files)} CSV files to convert")
    logger.info(f"Using {args.parallel} parallel workers, {args.compression} compression")
    
    # Parallel conversion
    total_rows = 0
    success_count = 0
    failed_files = []
    
    with ThreadPoolExecutor(max_workers=args.parallel) as executor:
        futures = {
            executor.submit(
                convert_csv_to_parquet,
                csv_file,
                output_dir,
                args.compression,
                args.chunk_size
            ): csv_file for csv_file in csv_files
        }
        
        for future in as_completed(futures):
            csv_file = futures[future]
            try:
                success, rows, output_path = future.result()
                if success:
                    total_rows += rows
                    success_count += 1
                else:
                    failed_files.append(csv_file.name)
            except Exception as e:
                logger.error(f"Exception processing {csv_file.name}: {e}")
                failed_files.append(csv_file.name)
    
    # Summary
    logger.info("")
    logger.info("=" * 80)
    logger.info(f"Conversion Summary:")
    logger.info(f"  Total CSV files: {len(csv_files)}")
    logger.info(f"  Successfully converted: {success_count}")
    logger.info(f"  Failed: {len(failed_files)}")
    logger.info(f"  Total rows processed: {total_rows:,}")
    if failed_files:
        logger.info(f"  Failed files: {', '.join(failed_files)}")
    logger.info(f"  Output directory: {output_dir}")
    logger.info("=" * 80)
    
    sys.exit(0 if len(failed_files) == 0 else 1)


if __name__ == '__main__':
    main()
