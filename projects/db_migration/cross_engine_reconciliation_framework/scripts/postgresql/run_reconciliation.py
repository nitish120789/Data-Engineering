#!/usr/bin/env python3
"""
PostgreSQL reconciliation Python runner.
Author: Nitish Anand Srivastava
"""

import argparse
import subprocess


def main():
    p = argparse.ArgumentParser(description='Run PostgreSQL reconciliation SQL')
    p.add_argument('--dsn', required=True)
    p.add_argument('--schema', default='public')
    p.add_argument('--table', default='orders')
    p.add_argument('--pk-col', default='id')
    p.add_argument('--updated-col', default='updated_at')
    p.add_argument('--deleted-flag-col', default='is_deleted')
    p.add_argument('--window-start', required=True)
    p.add_argument('--window-end', required=True)
    p.add_argument('--out-file', required=True)
    args = p.parse_args()

    cmd = [
        'psql', args.dsn,
        '-v', f'schema_name={args.schema}',
        '-v', f'table_name={args.table}',
        '-v', f'pk_col={args.pk_col}',
        '-v', f'updated_col={args.updated_col}',
        '-v', f'deleted_flag_col={args.deleted_flag_col}',
        '-v', f'window_start={args.window_start}',
        '-v', f'window_end={args.window_end}',
        '-f', 'scripts/postgresql/reconciliation.sql',
    ]

    with open(args.out_file, 'w', encoding='utf-8') as out:
        subprocess.run(cmd, stdout=out, stderr=subprocess.STDOUT, check=True)


if __name__ == '__main__':
    main()
