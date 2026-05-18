#!/usr/bin/env python3
"""
Database Guardrails Examples
Practical usage patterns and integration examples
"""

# ============================================================================
# EXAMPLE 1: Static Analysis in CI/CD Pipeline
# ============================================================================

def example_ci_pipeline_check():
    """
    Usage: Pre-deployment static analysis for pull requests
    """
    import subprocess
    import json
    
    # Your migration file
    sql_file = 'migrations/add_customer_email_idx.sql'
    
    # Run static analyzer
    result = subprocess.run([
        'python', 'db-guardrails/scripts/sql_static_analyzer.py',
        '--file', sql_file,
        '--strict',  # Fail on HIGH severity in strict mode
        '--format', 'json'
    ], capture_output=True, text=True)
    
    analysis = json.loads(result.stdout)
    
    if analysis['critical'] > 0:
        print(f"❌ BLOCKED: {analysis['critical']} critical violations")
        return False
    
    print("✓ Passed static analysis")
    return True


# ============================================================================
# EXAMPLE 2: Application Middleware Protection
# ============================================================================

def example_app_middleware():
    """
    Usage: Protect ORM queries at application layer
    """
    
    class DatabaseConnection:
        def __init__(self, config):
            self.config = config
            self.user = config['user']
        
        def execute(self, query, params=None):
            # Validate query before execution
            from db_guardrails import QueryGuard
            
            guard = QueryGuard(self.config['guardrails'])
            
            # Check if query is safe
            allowed, reason, risk_score = guard.can_execute(
                query=query,
                user=self.user,
                params=params
            )
            
            if not allowed:
                # Log and reject risky query
                self.log_security_event('QUERY_BLOCKED', query, reason)
                raise SecurityException(f'Query blocked: {reason} (Risk: {risk_score})')
            
            # Log all mutations
            if any(op in query.upper() for op in ['DELETE', 'UPDATE', 'INSERT']):
                self.log_mutation(query, self.user, risk_score)
            
            # Execute with timeout
            return self._execute_with_timeout(query, params, 30)
        
        def log_security_event(self, event_type, query, reason):
            print(f"[SECURITY] {event_type}: {reason}")
        
        def log_mutation(self, query, user, risk_score):
            print(f"[AUDIT] Mutation by {user} (risk={risk_score})")
        
        def _execute_with_timeout(self, query, params, timeout_sec):
            # Actual DB execution with timeout
            pass
    
    # Usage
    db = DatabaseConnection({
        'user': 'app_service',
        'guardrails': {
            'max_execution_seconds': 30,
            'block_delete_without_where': True,
            'enforcement_level': 'strict'
        }
    })
    
    # This will be blocked
    try:
        db.execute("DELETE FROM users WHERE status = 'inactive'")
        print("✓ Query executed (has WHERE clause)")
    except Exception as e:
        print(f"❌ {e}")


# ============================================================================
# EXAMPLE 3: ORM Query Builder Integration
# ============================================================================

def example_orm_integration():
    """
    Usage: SQLAlchemy/Django ORM with guardrails
    """
    
    # Monkey-patch ORM query execution
    class SafeQueryExecutor:
        def __init__(self, original_execute):
            self.original_execute = original_execute
            from db_guardrails import QueryGuard
            self.guard = QueryGuard()
        
        def __call__(self, query, *args, **kwargs):
            # Convert ORM query to SQL string
            query_string = str(query)
            
            # Validate
            allowed, reason, _ = self.guard.can_execute(query_string)
            
            if not allowed:
                raise ValueError(f'Guardrails violation: {reason}')
            
            # Execute original
            return self.original_execute(query, *args, **kwargs)
    
    # For Django ORM:
    # from django.db import connection
    # connection.execute = SafeQueryExecutor(connection.execute)


# ============================================================================
# EXAMPLE 4: Mutation Approval Workflow
# ============================================================================

def example_mutation_approval():
    """
    Usage: Require DBA approval for risky mutations
    """
    
    class MutationApprovalWorkflow:
        def __init__(self, db_connection):
            self.db = db_connection
        
        def submit_mutation(self, query, reason, requested_by):
            """Submit mutation for approval"""
            
            # Analyze risk
            from db_guardrails import QueryGuard
            guard = QueryGuard()
            allowed, reason, risk_score = guard.can_execute(query)
            
            # If low risk, auto-approve
            if risk_score < 10:
                return self.execute_mutation(query, requested_by)
            
            # Otherwise, create approval ticket
            approval_id = self.create_approval_ticket(
                query=query,
                reason=reason,
                requested_by=requested_by,
                risk_score=risk_score,
                status='PENDING'
            )
            
            # Notify DBA team
            self.notify_dba_team(approval_id, query, risk_score)
            
            return {
                'status': 'PENDING_APPROVAL',
                'approval_id': approval_id,
                'risk_score': risk_score
            }
        
        def approve_mutation(self, approval_id, approved_by):
            """DBA approves mutation"""
            mutation = self.get_approval(approval_id)
            
            # Update status
            self.db.execute("""
                UPDATE guardrail.mutation_approvals
                SET approval_status = 'APPROVED',
                    approved_by = ?,
                    approval_time = GETDATE()
                WHERE approval_id = ?
            """, [approved_by, approval_id])
            
            # Execute mutation
            return self.execute_mutation(mutation['query'], approved_by)
        
        def reject_mutation(self, approval_id, rejected_by, reason):
            """DBA rejects mutation"""
            self.db.execute("""
                UPDATE guardrail.mutation_approvals
                SET approval_status = 'REJECTED',
                    approved_by = ?,
                    approval_time = GETDATE(),
                    rejection_reason = ?
                WHERE approval_id = ?
            """, [rejected_by, reason, approval_id])
        
        def execute_mutation(self, query, executed_by):
            """Execute approved mutation"""
            result = self.db.execute(query)
            
            # Log execution
            self.log_execution(query, executed_by, result)
            return result
        
        def create_approval_ticket(self, **kwargs):
            pass
        
        def get_approval(self, approval_id):
            pass
        
        def notify_dba_team(self, approval_id, query, risk_score):
            pass
        
        def log_execution(self, query, executed_by, result):
            pass
    
    # Usage
    workflow = MutationApprovalWorkflow(db_connection)
    
    # Submit risky deletion
    result = workflow.submit_mutation(
        query="DELETE FROM audit_log WHERE date < '2020-01-01'",
        reason="Archiving old audit records",
        requested_by="app_service"
    )
    
    print(f"Mutation status: {result['status']}")
    if result['status'] == 'PENDING_APPROVAL':
        print(f"Approval ID: {result['approval_id']}")


# ============================================================================
# EXAMPLE 5: Git Pre-Commit Automation
# ============================================================================

def example_git_precommit():
    """
    Usage: Automatic checks before commit
    """
    import os
    
    # This would be .git/hooks/pre-commit
    
    def pre_commit_hook():
        import subprocess
        import tempfile
        
        # Get staged SQL files
        result = subprocess.run(
            ['git', 'diff', '--cached', '--name-only'],
            capture_output=True,
            text=True
        )
        
        sql_files = [f for f in result.stdout.split('\n') if f.endswith('.sql')]
        
        if not sql_files:
            return 0  # Nothing to check
        
        violations = 0
        
        for sql_file in sql_files:
            # Get staged content
            result = subprocess.run(
                ['git', 'show', f':{sql_file}'],
                capture_output=True,
                text=True
            )
            
            # Analyze
            check_result = subprocess.run([
                'python', 'db-guardrails/scripts/sql_static_analyzer.py',
                '--stdin', '--strict'
            ], input=result.stdout, capture_output=True)
            
            if check_result.returncode != 0:
                print(f"❌ {sql_file}: Pre-commit check failed")
                violations += 1
            else:
                print(f"✓ {sql_file}")
        
        return 1 if violations > 0 else 0


# ============================================================================
# EXAMPLE 6: Kubernetes Monitoring Pod
# ============================================================================

def example_k8s_monitoring():
    """
    Usage: Continuous database guardrails monitoring in Kubernetes
    """
    
    k8s_manifest = """
apiVersion: v1
kind: ConfigMap
metadata:
  name: db-guardrails-monitor
  namespace: database-ops
data:
  monitor.py: |
    import os
    import time
    import pyodbc
    from guardrails import MutationMonitor
    
    conn_str = f"Driver={{ODBC Driver 17 for SQL Server}};Server={os.getenv('DB_HOST')};Database={os.getenv('DB_NAME')};Uid={os.getenv('DB_USER')};Pwd={os.getenv('DB_PASSWORD')}"
    
    monitor = MutationMonitor(conn_str)
    
    while True:
        violations = monitor.check_recent_mutations(hours=1)
        
        if violations:
            alert_to_slack(f"Found {len(violations)} mutations in last hour")
        
        time.sleep(300)  # Check every 5 minutes
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-guardrails-monitor
  namespace: database-ops
spec:
  schedule: "*/5 * * * *"  # Every 5 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: monitor
            image: python:3.10
            env:
            - name: DB_HOST
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: host
            - name: DB_NAME
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: database
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: user
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: password
            volumeMounts:
            - name: config
              mountPath: /app/config
            command: ["python", "/app/config/monitor.py"]
          restartPolicy: OnFailure
          volumes:
          - name: config
            configMap:
              name: db-guardrails-monitor
"""
    
    return k8s_manifest


# ============================================================================
# EXAMPLE 7: Risk Scoring and Analytics
# ============================================================================

def example_risk_analytics():
    """
    Usage: Analyze guardrails violations and trends
    """
    
    import pandas as pd
    from datetime import datetime, timedelta
    
    class GuardrailsAnalytics:
        def __init__(self, db_connection):
            self.db = db_connection
        
        def get_violation_trends(self, days=30):
            """Get violation trends over time"""
            
            query = """
            SELECT 
                CAST(audit_timestamp AS DATE) AS date,
                violation_type,
                COUNT(*) AS count,
                AVG(risk_score) AS avg_risk
            FROM guardrail.violations
            WHERE audit_timestamp > DATEADD(DAY, ?, GETDATE())
            GROUP BY CAST(audit_timestamp AS DATE), violation_type
            ORDER BY date DESC
            """
            
            df = pd.read_sql(query, self.db, params=[-days])
            return df
        
        def get_high_risk_users(self):
            """Identify users with risky query patterns"""
            
            query = """
            SELECT TOP 10
                user_id,
                COUNT(*) AS violation_count,
                AVG(risk_score) AS avg_risk,
                MAX(audit_timestamp) AS last_violation
            FROM guardrail.violations
            WHERE audit_timestamp > DATEADD(DAY, -30, GETDATE())
            GROUP BY user_id
            ORDER BY avg_risk DESC
            """
            
            return pd.read_sql(query, self.db)
        
        def get_false_positive_rate(self):
            """Calculate false positive rate"""
            
            query = """
            SELECT
                COUNT(CASE WHEN was_false_positive = 1 THEN 1 END) AS false_positives,
                COUNT(*) AS total_violations,
                CAST(COUNT(CASE WHEN was_false_positive = 1 THEN 1 END) * 100.0 / 
                     COUNT(*) AS DECIMAL(5,2)) AS false_positive_rate
            FROM guardrail.violations
            WHERE audit_timestamp > DATEADD(DAY, -30, GETDATE())
            """
            
            return pd.read_sql(query, self.db).iloc[0]
        
        def effectiveness_report(self):
            """Generate monthly guardrails effectiveness report"""
            
            report = {
                'period': 'Last 30 Days',
                'trends': self.get_violation_trends(),
                'high_risk_users': self.get_high_risk_users(),
                'false_positive_rate': self.get_false_positive_rate(),
                'recommendations': self._generate_recommendations()
            }
            
            return report
        
        def _generate_recommendations(self):
            """Generate improvement recommendations"""
            fp_rate = self.get_false_positive_rate()['false_positive_rate']
            
            if fp_rate > 10:
                return ["High false positive rate. Consider adjusting risk thresholds."]
            
            return ["All systems nominal."]


if __name__ == '__main__':
    print("Database Guardrails Examples")
    print("See individual functions for usage patterns")
