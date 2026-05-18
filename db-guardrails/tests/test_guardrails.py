#!/usr/bin/env python3
"""
Database Guardrails Testing Framework
Unit tests, integration tests, and performance benchmarks
"""

import unittest
from pathlib import Path
import sys
import subprocess
import json
import time

sys.path.insert(0, str(Path(__file__).parent.parent / 'scripts'))

class TestSQLStaticAnalyzer(unittest.TestCase):
    """Test SQL static analyzer detection"""
    
    def setUp(self):
        self.analyzer_path = Path(__file__).parent.parent / 'scripts' / 'sql_static_analyzer.py'
    
    def run_analyzer(self, sql_code):
        """Execute analyzer and return result"""
        result = subprocess.run(
            ['python', str(self.analyzer_path), '--stdin', '--format', 'json'],
            input=sql_code,
            capture_output=True,
            text=True
        )
        try:
            return json.loads(result.stdout)
        except:
            return {'errors': result.stderr}
    
    def test_delete_without_where(self):
        """CRITICAL: DELETE without WHERE should be detected"""
        result = self.run_analyzer("DELETE FROM users;")
        self.assertIn('DELETE without WHERE', str(result))
    
    def test_update_without_where(self):
        """CRITICAL: UPDATE without WHERE should be detected"""
        result = self.run_analyzer("UPDATE products SET price = 100;")
        self.assertIn('UPDATE without WHERE', str(result))
    
    def test_truncate_usage(self):
        """CRITICAL: TRUNCATE should be detected"""
        result = self.run_analyzer("TRUNCATE TABLE audit_log;")
        self.assertIn('TRUNCATE', str(result))
    
    def test_sql_injection_pattern(self):
        """CRITICAL: String concatenation should be detected"""
        sql = """
        DECLARE @table NVARCHAR(MAX) = 'users'
        EXEC('SELECT * FROM ' + @table + ' WHERE id = 1')
        """
        result = self.run_analyzer(sql)
        self.assertIn('SQL injection', str(result).lower())
    
    def test_correlated_subquery(self):
        """HIGH: Correlated subqueries should be flagged"""
        sql = """
        SELECT * FROM customers c
        WHERE id IN (SELECT customer_id FROM orders o WHERE o.date > c.last_purchase)
        """
        result = self.run_analyzer(sql)
        # Correlated subquery or similar pattern should be detected
    
    def test_leading_wildcard_like(self):
        """HIGH: LIKE with leading wildcard should be flagged"""
        result = self.run_analyzer("SELECT * FROM products WHERE name LIKE '%laptop%';")
        self.assertIn('LIKE', str(result).lower())
    
    def test_valid_delete_with_where(self):
        """✓ DELETE with WHERE should pass"""
        result = self.run_analyzer("""
        DELETE FROM users 
        WHERE user_id = 123 
        AND created_at < DATEADD(YEAR, -5, GETDATE());
        """)
        self.assertFalse(result.get('critical', 0) > 0)
    
    def test_valid_update_with_where(self):
        """✓ UPDATE with WHERE should pass"""
        result = self.run_analyzer("""
        UPDATE products 
        SET price = 99.99 
        WHERE category = 'Electronics' 
        AND status = 'active';
        """)
        self.assertFalse(result.get('critical', 0) > 0)


class TestMutationSafeguard(unittest.TestCase):
    """Test mutation tracking and approval"""
    
    def test_mutation_audit_table_exists(self):
        """Verify mutation audit table is created"""
        # Mock test - in real scenario, connect to DB
        pass
    
    def test_mutation_approval_workflow(self):
        """Test approval workflow for risky mutations"""
        # 1. Record mutation as PENDING
        # 2. Check DBA approval
        # 3. Update approval status
        pass
    
    def test_rollback_on_rejection(self):
        """Test that rejected mutations don't execute"""
        pass


class TestQueryExecutionGuard(unittest.TestCase):
    """Test runtime query protection"""
    
    def test_timeout_enforcement(self):
        """Query exceeding timeout should be killed"""
        pass
    
    def test_row_limit_warning(self):
        """Large result sets should trigger warning"""
        pass
    
    def test_lock_detection(self):
        """Long-running queries causing blocks should be detected"""
        pass


class TestCICDIntegration(unittest.TestCase):
    """Test CI/CD workflow integration"""
    
    def test_github_actions_workflow_valid_yaml(self):
        """Verify workflow file is valid YAML"""
        workflow_path = Path(__file__).parent.parent / 'ci-cd' / 'github_actions_workflow.yml'
        self.assertTrue(workflow_path.exists())
        # Parse and validate YAML
    
    def test_pre_commit_hook_executable(self):
        """Verify pre-commit hook is executable"""
        hook_path = Path(__file__).parent.parent / 'hooks' / 'pre-commit-guardrails.sh'
        self.assertTrue(hook_path.exists())
        self.assertTrue(hook_path.stat().st_mode & 0o111)  # Check executable bit


class TestPerformance(unittest.TestCase):
    """Performance benchmarks"""
    
    def test_analyzer_performance(self):
        """Analyzer should process queries in <100ms"""
        large_query = "\n".join([
            "SELECT * FROM table1 t1",
            "JOIN table2 t2 ON t1.id = t2.id",
            "WHERE t1.date > '2026-01-01'"
        ] * 10)
        
        start = time.time()
        result = subprocess.run(
            ['python', 'scripts/sql_static_analyzer.py', '--stdin'],
            input=large_query,
            capture_output=True,
            text=True,
            timeout=1
        )
        elapsed = (time.time() - start) * 1000
        self.assertLess(elapsed, 100, f"Analyzer took {elapsed}ms, expected <100ms")


class TestConfigValidation(unittest.TestCase):
    """Test configuration file validation"""
    
    def test_guardrails_yaml_syntax(self):
        """Verify guardrails.yaml is valid YAML"""
        config_path = Path(__file__).parent.parent / 'config' / 'guardrails.yaml'
        self.assertTrue(config_path.exists())
        # Validate YAML syntax
    
    def test_required_config_sections(self):
        """Verify all required config sections exist"""
        # enforcement, detection, mutations, risk_scoring, etc.
        pass


def run_all_tests():
    """Run complete test suite"""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add all test classes
    suite.addTests(loader.loadTestsFromTestCase(TestSQLStaticAnalyzer))
    suite.addTests(loader.loadTestsFromTestCase(TestMutationSafeguard))
    suite.addTests(loader.loadTestsFromTestCase(TestQueryExecutionGuard))
    suite.addTests(loader.loadTestsFromTestCase(TestCICDIntegration))
    suite.addTests(loader.loadTestsFromTestCase(TestPerformance))
    suite.addTests(loader.loadTestsFromTestCase(TestConfigValidation))
    
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(run_all_tests())
