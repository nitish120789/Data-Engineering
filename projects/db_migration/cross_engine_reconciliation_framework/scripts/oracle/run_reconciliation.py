#!/usr/bin/env python3
"""
Oracle reconciliation Python runner.
Author: Nitish Anand Srivastava
"""

import argparse
import subprocess


def main():
    p = argparse.ArgumentParser(description='Run Oracle reconciliation SQL')
    p.add_argument('--conn', required=True, help='sqlplus connection string user/pass@host/service')
    p.add_argument('--schema', required=True)
    p.add_argument('--table', required=True)
    p.add_argument('--pk-col', default='ID')
    p.add_argument('--updated-col', default='UPDATED_AT')
    p.add_argument('--deleted-flag-col', default='IS_DELETED')
    p.add_argument('--window-start', required=True)
    p.add_argument('--window-end', required=True)
    p.add_argument('--out-file', required=True)
    args = p.parse_args()

    cmd = [
        'sqlplus', '-s', args.conn,
        '@scripts/oracle/reconciliation.sql',
        args.schema, args.table, args.pk_col, args.updated_col,
        args.deleted_flag_col, args.window_start, args.window_end,
    ]

    with open(args.out_file, 'w', encoding='utf-8') as out:
        subprocess.run(cmd, stdout=out, stderr=subprocess.STDOUT, check=True)


if __name__ == '__main__':
    main()
