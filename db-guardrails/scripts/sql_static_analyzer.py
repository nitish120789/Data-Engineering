#!/usr/bin/env python3
"""
SQL Static Analysis and Pre-Deployment Validation
Detects risky SQL patterns before they reach the database.

Usage:
    python sql_static_analyzer.py --file query.sql --config guardrails.yaml
    python sql_static_analyzer.py --stdin < query.sql --strict
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import List, Tuple

class SQLAnalyzer:
    def __init__(self, strict_mode: bool = False):
        self.strict_mode = strict_mode
        self.findings: List[dict] = []
        
        # Critical patterns (must fail in strict mode)
        self.critical_patterns = [
            (r'\bDELETE\s+FROM\s+\w+\s*;', 'DELETE without WHERE clause'),
            (r'\bUPDATE\s+\w+\s+SET\b(?!.*\bWHERE\b)', 'UPDATE without WHERE clause'),
            (r'(?:EXEC|EXECUTE)\s*\(\s*[\'"].*\+.*[\'"]', 'SQL injection: string concatenation'),
            (r'\bTRUNCATE\s+TABLE\b', 'TRUNCATE statement (bypasses audit)'),
            (r'(?:SELECT|INSERT|UPDATE|DELETE).*;\s*(?:SELECT|INSERT|UPDATE|DELETE)', 'Multiple statements in batch'),
        ]
        
        # High severity patterns
        self.high_patterns = [
            (r'\bSELECT\s+\*\s+FROM\s+\w+\s*;', 'SELECT * (use column list)'),
            (r'\bCONVERT\s*\([^)]*,\s*\w+\s*\)\s*=', 'Type conversion in WHERE (non-sargable)'),
            (r'\bWHERE\s+.*\bOR\b.*=', 'OR in WHERE clause (may disable index)'),
            (r'\bLIKE\s+[\'"]%', "LIKE with leading wildcard (full table scan)"),
            (r'\bNOT\s+IN\s*\(', 'NOT IN with subquery (use NOT EXISTS instead)'),
        ]
        
        # Medium severity patterns
        self.medium_patterns = [
            (r'\bCOUNT\(\*\)', 'COUNT(*) without WHERE (verify intent)'),
            (r'\bEXISTS.*SELECT\s+\*', 'EXISTS with SELECT * (use column reference)'),
            (r'--.*AI.*generated', 'AI-generated marker found (manual review needed)'),
            (r'\bGETDATE\(\)', 'GETDATE() use (prefer SYSDATETIME for precision)'),
            (r'\b@@IDENTITY\b', '@@IDENTITY (use SCOPE_IDENTITY instead)'),
        ]
    
    def analyze_file(self, filepath: str) -> Tuple[bool, List[dict]]:
        """Analyze SQL file and return pass/fail + findings."""
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                sql_text = f.read()
            return self.analyze_text(sql_text)
        except FileNotFoundError:
            self.findings.append({
                'severity': 'ERROR',
                'message': f'File not found: {filepath}',
                'line': 0,
                'column': 0
            })
            return False, self.findings
    
    def analyze_text(self, sql_text: str) -> Tuple[bool, List[dict]]:
        """Analyze SQL text directly."""
        self.findings = []
        lines = sql_text.split('\n')
        
        # Check critical patterns
        for pattern, description in self.critical_patterns:
            matches = list(re.finditer(pattern, sql_text, re.IGNORECASE))
            for match in matches:
                line_num = sql_text[:match.start()].count('\n') + 1
                self.findings.append({
                    'severity': 'CRITICAL',
                    'message': description,
                    'line': line_num,
                    'pattern': pattern,
                    'matched_text': match.group(0)
                })
        
        # Check high severity patterns
        for pattern, description in self.high_patterns:
            matches = list(re.finditer(pattern, sql_text, re.IGNORECASE))
            for match in matches:
                line_num = sql_text[:match.start()].count('\n') + 1
                self.findings.append({
                    'severity': 'HIGH',
                    'message': description,
                    'line': line_num,
                    'pattern': pattern,
                    'matched_text': match.group(0)
                })
        
        # Check medium severity patterns
        for pattern, description in self.medium_patterns:
            matches = list(re.finditer(pattern, sql_text, re.IGNORECASE))
            for match in matches:
                line_num = sql_text[:match.start()].count('\n') + 1
                self.findings.append({
                    'severity': 'MEDIUM',
                    'message': description,
                    'line': line_num,
                    'pattern': pattern,
                    'matched_text': match.group(0)
                })
        
        # Determine pass/fail
        critical_count = len([f for f in self.findings if f['severity'] == 'CRITICAL'])
        high_count = len([f for f in self.findings if f['severity'] == 'HIGH'])
        
        if critical_count > 0:
            return False, self.findings
        
        if self.strict_mode and high_count > 0:
            return False, self.findings
        
        return True, self.findings
    
    def report_json(self) -> str:
        """Return findings as JSON."""
        return json.dumps({
            'findings_count': len(self.findings),
            'critical': len([f for f in self.findings if f['severity'] == 'CRITICAL']),
            'high': len([f for f in self.findings if f['severity'] == 'HIGH']),
            'medium': len([f for f in self.findings if f['severity'] == 'MEDIUM']),
            'findings': self.findings
        }, indent=2)
    
    def report_text(self) -> str:
        """Return findings as human-readable text."""
        lines = ['=== SQL Static Analysis Report ===\n']
        
        if not self.findings:
            lines.append('✓ No issues found\n')
            return ''.join(lines)
        
        lines.append(f'Total findings: {len(self.findings)}\n')
        lines.append(f'  CRITICAL: {len([f for f in self.findings if f["severity"] == "CRITICAL"])}')
        lines.append(f'  HIGH: {len([f for f in self.findings if f["severity"] == "HIGH"])}')
        lines.append(f'  MEDIUM: {len([f for f in self.findings if f["severity"] == "MEDIUM"])}\n')
        
        for finding in sorted(self.findings, key=lambda x: {'CRITICAL': 0, 'HIGH': 1, 'MEDIUM': 2}.get(x['severity'], 3)):
            lines.append(f"\n[{finding['severity']}] Line {finding['line']}: {finding['message']}")
            lines.append(f"  Pattern: {finding['pattern']}")
            lines.append(f"  Match: {finding['matched_text']}")
        
        return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description='SQL Static Analysis for AI-Generated Code Detection')
    parser.add_argument('--file', help='SQL file to analyze')
    parser.add_argument('--stdin', action='store_true', help='Read SQL from stdin')
    parser.add_argument('--strict', action='store_true', help='Fail on HIGH severity findings')
    parser.add_argument('--format', choices=['text', 'json'], default='text', help='Output format')
    parser.add_argument('--config', help='Configuration file (YAML)')
    
    args = parser.parse_args()
    
    if not args.file and not args.stdin:
        parser.print_help()
        sys.exit(1)
    
    analyzer = SQLAnalyzer(strict_mode=args.strict)
    
    if args.file:
        passed, findings = analyzer.analyze_file(args.file)
    else:
        sql_text = sys.stdin.read()
        passed, findings = analyzer.analyze_text(sql_text)
    
    if args.format == 'json':
        print(analyzer.report_json())
    else:
        print(analyzer.report_text())
    
    sys.exit(0 if passed else 1)


if __name__ == '__main__':
    main()
