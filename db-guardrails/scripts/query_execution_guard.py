#!/usr/bin/env python3
"""
Query Execution Guard - Prevents risky queries from running
Can be deployed as:
  - Application middleware interceptor
  - Database driver proxy
  - Connection pooler guardian
"""

import argparse
import sys
from dataclasses import dataclass
from typing import List, Optional

@dataclass
class QueryGuardConfig:
    """Configuration for query execution guards."""
    max_execution_seconds: int = 30
    max_memory_mb: int = 1024
    max_row_output: int = 1000000
    max_tables_per_query: int = 10
    block_delete_without_where: bool = True
    block_update_without_where: bool = True
    block_truncate: bool = True
    block_dynamic_sql: bool = True
    whitelist_users: List[str] = None
    allowed_operations: List[str] = None

class QueryGuard:
    def __init__(self, config: QueryGuardConfig = None):
        self.config = config or QueryGuardConfig()
        self.violation_log: List[dict] = []
    
    def can_execute(self, query: str, user: str = 'unknown', context: dict = None) -> tuple:
        """
        Determine if query can safely execute.
        Returns (allowed: bool, reason: str, risk_score: int)
        """
        risk_score = 0
        violations = []
        
        # Rule 1: DELETE without WHERE
        if self.config.block_delete_without_where:
            if 'DELETE' in query.upper() and 'WHERE' not in query.upper():
                risk_score += 100
                violations.append('DELETE without WHERE clause')
        
        # Rule 2: UPDATE without WHERE
        if self.config.block_update_without_where:
            if 'UPDATE' in query.upper() and 'WHERE' not in query.upper():
                risk_score += 100
                violations.append('UPDATE without WHERE clause')
        
        # Rule 3: TRUNCATE
        if self.config.block_truncate:
            if 'TRUNCATE' in query.upper():
                risk_score += 100
                violations.append('TRUNCATE statement blocked')
        
        # Rule 4: Dynamic SQL
        if self.config.block_dynamic_sql:
            if 'EXEC(' in query.upper() or 'EXECUTE(' in query.upper():
                if '+' in query or "||" in query:
                    risk_score += 90
                    violations.append('Dynamic SQL detected (potential SQL injection)')
        
        # Log violation
        if violations:
            self.violation_log.append({
                'user': user,
                'query_preview': query[:100],
                'violations': violations,
                'risk_score': risk_score
            })
        
        allowed = risk_score < 100
        reason = '; '.join(violations) if violations else 'OK'
        
        return allowed, reason, risk_score
    
    def get_violation_report(self) -> str:
        """Generate violation report."""
        if not self.violation_log:
            return 'No violations logged.'
        
        lines = ['=== Query Execution Violations ===\n']
        for log_entry in self.violation_log:
            lines.append(f"User: {log_entry['user']}")
            lines.append(f"Risk Score: {log_entry['risk_score']}")
            lines.append(f"Query: {log_entry['query_preview']}")
            lines.append(f"Violations: {', '.join(log_entry['violations'])}\n")
        
        return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description='Query Execution Guard')
    parser.add_argument('--query', help='Query to evaluate')
    parser.add_argument('--user', default='unknown', help='User executing query')
    parser.add_argument('--strict', action='store_true', help='Use strict rules')
    parser.add_argument('--report', action='store_true', help='Show violation report')
    
    args = parser.parse_args()
    
    config = QueryGuardConfig()
    if args.strict:
        config.max_execution_seconds = 10
        config.max_row_output = 100000
    
    guard = QueryGuard(config)
    
    if not args.query:
        print('Usage: python query_execution_guard.py --query "SELECT ..." --user app_user')
        sys.exit(1)
    
    allowed, reason, risk_score = guard.can_execute(args.query, args.user)
    
    print(f'Query Allowed: {"✓ YES" if allowed else "✗ NO"}')
    print(f'Risk Score: {risk_score}/100')
    print(f'Reason: {reason}')
    
    if args.report:
        print('\n' + guard.get_violation_report())
    
    sys.exit(0 if allowed else 1)


if __name__ == '__main__':
    main()
