#!/usr/bin/env python3
"""
SQL Server reconciliation Python runner.
Author: Nitish Anand Srivastava
"""

import argparse
import subprocess


def main():
    p = argparse.ArgumentParser(description='Run SQL Server reconciliation SQL')
    p.add_argument('--host', required=True)
    p.add_argument('--database', required=True)
    p.add_argument('--schema', default='dbo')
    p.add_argument('--table', default='orders')
    p.add_argument('--pk-col', default='id')
    p.add_argument('--updated-col', default='updated_at')
    p.add_argument('--deleted-flag-col', default='is_deleted')
    p.add_argument('--window-start', required=True)
    p.add_argument('--window-end', required=True)
    p.add_argument('--out-file', required=True)
    args = p.parse_args()

    cmd = [
        'sqlcmd', '-S', args.host, '-d', args.database, '-E',
        '-v',
        f'SCHEMA_NAME={args.schema}',
        f'TABLE_NAME={args.table}',
        f'PK_COL={args.pk_col}',
        f'UPDATED_COL={args.updated_col}',
        f'DELETED_FLAG_COL={args.deleted_flag_col}',
        f'WINDOW_START={args.window_start}',
        f'WINDOW_END={args.window_end}',
        '-i', 'scripts/sqlserver/reconciliation.sql',
    ]

    with open(args.out_file, 'w', encoding='utf-8') as out:
        subprocess.run(cmd, stdout=out, stderr=subprocess.STDOUT, check=True)


if __name__ == '__main__':
    main()
