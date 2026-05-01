#!/usr/bin/env python3
"""
Cross-engine reconciliation result comparator.
Author: Nitish Anand Srivastava

Input:
- Source summary CSV
- Target summary CSV

Expected CSV columns:
schema_name,table_name,row_count,hash_sum,updated_count,deleted_count,run_ts
"""

import argparse
import csv
import json
from pathlib import Path


def key(row):
    return (row.get('schema_name', ''), row.get('table_name', ''))


def to_int(v):
    if v is None or v == '':
        return 0
    return int(float(v))


def compare_rows(src, tgt):
    result = {
        'schema_name': src.get('schema_name') or tgt.get('schema_name'),
        'table_name': src.get('table_name') or tgt.get('table_name'),
        'count_match': True,
        'hash_match': True,
        'update_match': True,
        'delete_match': True,
        'deltas': {},
        'severity': 'OK',
    }

    src_count = to_int(src.get('row_count'))
    tgt_count = to_int(tgt.get('row_count'))
    src_hash = str(src.get('hash_sum', ''))
    tgt_hash = str(tgt.get('hash_sum', ''))
    src_upd = to_int(src.get('updated_count'))
    tgt_upd = to_int(tgt.get('updated_count'))
    src_del = to_int(src.get('deleted_count'))
    tgt_del = to_int(tgt.get('deleted_count'))

    if src_count != tgt_count:
        result['count_match'] = False
        result['deltas']['row_count_delta'] = tgt_count - src_count

    if src_hash != tgt_hash:
        result['hash_match'] = False

    if src_upd != tgt_upd:
        result['update_match'] = False
        result['deltas']['update_delta'] = tgt_upd - src_upd

    if src_del != tgt_del:
        result['delete_match'] = False
        result['deltas']['delete_delta'] = tgt_del - src_del

    if not result['count_match'] and not result['hash_match']:
        result['severity'] = 'SEV1'
    elif not result['count_match'] or not result['hash_match']:
        result['severity'] = 'SEV2'
    elif not result['update_match'] or not result['delete_match']:
        result['severity'] = 'SEV2'

    return result


def load_csv(path):
    with open(path, 'r', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def main():
    parser = argparse.ArgumentParser(description='Compare source/target reconciliation summaries')
    parser.add_argument('--source-summary', required=True)
    parser.add_argument('--target-summary', required=True)
    parser.add_argument('--out-json', required=True)
    parser.add_argument('--out-csv', required=True)
    args = parser.parse_args()

    src_rows = load_csv(args.source_summary)
    tgt_rows = load_csv(args.target_summary)

    src_map = {key(r): r for r in src_rows}
    tgt_map = {key(r): r for r in tgt_rows}

    all_keys = sorted(set(src_map.keys()) | set(tgt_map.keys()))

    report = []
    for k in all_keys:
        src = src_map.get(k, {})
        tgt = tgt_map.get(k, {})
        row = compare_rows(src, tgt)
        report.append(row)

    out_json = Path(args.out_json)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    with open(out_json, 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=2)

    out_csv = Path(args.out_csv)
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with open(out_csv, 'w', encoding='utf-8', newline='') as f:
        cols = [
            'schema_name', 'table_name', 'count_match', 'hash_match',
            'update_match', 'delete_match', 'severity', 'deltas'
        ]
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in report:
            w.writerow({
                'schema_name': r['schema_name'],
                'table_name': r['table_name'],
                'count_match': r['count_match'],
                'hash_match': r['hash_match'],
                'update_match': r['update_match'],
                'delete_match': r['delete_match'],
                'severity': r['severity'],
                'deltas': json.dumps(r.get('deltas', {}), separators=(',', ':')),
            })

    sev1 = sum(1 for r in report if r['severity'] == 'SEV1')
    sev2 = sum(1 for r in report if r['severity'] == 'SEV2')
    print(f'Reconciliation completed: {len(report)} tables, SEV1={sev1}, SEV2={sev2}')


if __name__ == '__main__':
    main()
