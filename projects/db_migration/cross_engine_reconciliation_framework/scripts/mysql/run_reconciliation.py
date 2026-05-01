#!/usr/bin/env python3
"""
MySQL reconciliation Python runner.
Author: Nitish Anand Srivastava
"""

import argparse
import subprocess
import tempfile


def main():
    p = argparse.ArgumentParser(description='Run MySQL reconciliation SQL')
    p.add_argument('--mysql-cli', required=True, help='mysql CLI command prefix, e.g. mysql -h host -u user -p*** db')
    p.add_argument('--schema', required=True)
    p.add_argument('--table', required=True)
    p.add_argument('--pk-col', default='id')
    p.add_argument('--updated-col', default='updated_at')
    p.add_argument('--deleted-flag-col', default='is_deleted')
    p.add_argument('--window-start', required=True)
    p.add_argument('--window-end', required=True)
    p.add_argument('--out-file', required=True)
    args = p.parse_args()

    with open('scripts/mysql/reconciliation.sql', 'r', encoding='utf-8') as f:
        sql = f.read()

    preamble = '\n'.join([
        f"SET @schema_name='{args.schema}';",
        f"SET @table_name='{args.table}';",
        f"SET @pk_col='{args.pk_col}';",
        f"SET @updated_col='{args.updated_col}';",
        f"SET @deleted_flag_col='{args.deleted_flag_col}';",
        f"SET @window_start='{args.window_start}';",
        f"SET @window_end='{args.window_end}';",
        ''
    ])

    with tempfile.NamedTemporaryFile('w', delete=False, encoding='utf-8', suffix='.sql') as tmp:
        tmp.write(preamble)
        tmp.write(sql)
        tmp_path = tmp.name

    cmd = f"{args.mysql_cli} < \"{tmp_path}\""
    with open(args.out_file, 'w', encoding='utf-8') as out:
        subprocess.run(cmd, shell=True, stdout=out, stderr=subprocess.STDOUT, check=True)


if __name__ == '__main__':
    main()
