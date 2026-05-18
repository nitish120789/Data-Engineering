#!/bin/bash
# Pre-commit hook for database guardrails
# Install: cp db-guardrails/hooks/pre-commit-guardrails.sh .git/hooks/pre-commit

set -e

GUARDRAILS_DIR="db-guardrails"
PYTHON_BIN=${PYTHON_BIN:-python3}

echo "🛡️ Running Database Guardrails Pre-Commit Checks..."

# Check for SQL files
SQL_FILES=$(git diff --cached --name-only | grep -E '\.sql$' || true)

if [ -z "$SQL_FILES" ]; then
    echo "✓ No SQL files to check"
    exit 0
fi

# Run static analysis on each SQL file
VIOLATIONS=0

for sql_file in $SQL_FILES; do
    echo "Analyzing: $sql_file"
    
    if $PYTHON_BIN "$GUARDRAILS_DIR/scripts/sql_static_analyzer.py" \
        --file "$sql_file" \
        --strict \
        --format json > /tmp/guardrail_report.json 2>&1; then
        echo "  ✓ Passed"
    else
        echo "  ❌ Failed - Critical violations found"
        cat /tmp/guardrail_report.json
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done

if [ $VIOLATIONS -gt 0 ]; then
    echo ""
    echo "❌ Pre-commit check failed: $VIOLATIONS file(s) have critical issues"
    echo "Fix the issues or use: git commit --no-verify (not recommended)"
    exit 1
fi

echo ""
echo "✓ All guardrails checks passed"
exit 0
