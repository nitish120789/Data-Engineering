# Troubleshooting
## Oracle to Amazon Aurora PostgreSQL Migration with AWS DMS

## 1. Schema Conversion Issues

Issue: ora2pg output compiles but application logic fails
- Cause:
  - semantic difference, not syntax failure
- Action:
  - replay representative test cases and compare Oracle versus Aurora outputs

Issue: converted numeric columns overflow or lose scale
- Cause:
  - unsafe NUMBER mapping
- Action:
  - re-profile source values and adjust target datatype explicitly

## 2. AWS DMS Full Load Issues

Issue: full load table failures
- Checks:
  - unsupported datatypes
  - target constraint violations
  - insufficient replication instance size
- Actions:
  - exclude and remediate unsupported columns or redesign load path
  - defer constraints if appropriate
  - scale replication instance

Issue: LOB columns replicate slowly or fail
- Checks:
  - DMS LOB mode and task logs
- Actions:
  - increase LOB size settings or switch mode based on object profile
  - test with representative largest rows

## 3. CDC Issues

Issue: CDC latency grows continuously
- Checks:
  - source redo churn
  - target CPU/IO saturation
  - repeated apply errors
- Actions:
  - increase target capacity
  - tune DMS task settings
  - isolate problematic tables for remediation

Issue: updates/deletes not applying correctly
- Checks:
  - tables without PKs
  - supplemental logging coverage
- Actions:
  - remediate PK gaps or define deterministic key strategy
  - validate supplemental logging on affected tables

## 4. Validation and Cutover Issues

Issue: row counts match but business report differs
- Cause:
  - semantic difference in joins, dates, rounding, or NULL handling
- Action:
  - compare canonical report SQL side by side and fix semantics before cutover

Issue: duplicate key errors after go-live
- Cause:
  - sequences not reseeded to target max value
- Action:
  - run sequence reseed and repeat write-path tests

## 5. Escalation Guidance

Escalate immediately for:
- Class A mismatch
- repeated DMS restart loops
- hidden source write path after freeze
- rollback decision point approaching without clear resolution

## Author

Author: Nitish Anand Srivastava
