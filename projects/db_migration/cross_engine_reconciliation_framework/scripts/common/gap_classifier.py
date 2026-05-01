#!/usr/bin/env python3
"""
Classifies reconciliation mismatches into remediation classes.
Author: Nitish Anand Srivastava
"""

import argparse
import csv
import json


def classify(row):
    count_match = row.get('count_match', '').lower() == 'true'
    hash_match = row.get('hash_match', '').lower() == 'true'
    update_match = row.get('update_match', '').lower() == 'true'
    delete_match = row.get('delete_match', '').lower() == 'true'

    if not count_match and not hash_match:
        return 'CLASS-A', 'Re-extract and replay missing/extra key ranges; then hash validate'
    if count_match and not hash_match:
        return 'CLASS-B', 'Run row-level diff and targeted UPDATE remediation'
    if (not update_match) or (not delete_match):
        return 'CLASS-C', 'Replay CDC from safe checkpoint and validate operation parity'
    return 'OK', 'No remediation required'


def main():
    parser = argparse.ArgumentParser(description='Classify reconciliation gaps')
    parser.add_argument('--input-csv', required=True)
    parser.add_argument('--output-csv', required=True)
    args = parser.parse_args()

    with open(args.input_csv, 'r', encoding='utf-8') as f:
        rows = list(csv.DictReader(f))

    out_rows = []
    for row in rows:
        cls, action = classify(row)
        row['gap_class'] = cls
        row['recommended_action'] = action
        out_rows.append(row)

    cols = list(out_rows[0].keys()) if out_rows else [
        'schema_name', 'table_name', 'gap_class', 'recommended_action'
    ]
    with open(args.output_csv, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(out_rows)

    summary = {}
    for r in out_rows:
        summary[r['gap_class']] = summary.get(r['gap_class'], 0) + 1
    print('Gap classification summary:', json.dumps(summary, separators=(',', ':')))


if __name__ == '__main__':
    main()
