# Schema Conversion Guide
## Oracle to Azure PostgreSQL Flexible Server

## 1. Conversion Objectives

- Preserve business semantics first, then optimize for PostgreSQL performance.
- Remove Oracle-specific coupling that blocks predictable operations.
- Ensure converted DDL is idempotent and deployment-safe.

## 2. Conversion Workflow

1. Extract source DDL and metadata from Oracle.
2. Run automated conversion baseline (tool-assisted).
3. Perform manual review for complex object classes.
4. Produce canonical PostgreSQL DDL package.
5. Execute integration tests with representative workload.
6. Record unresolved gaps with owner and mitigation.

## 3. Data Type Mapping Considerations

Common patterns:
- NUMBER(p,0) -> bigint/integer when safe, otherwise numeric(p,0)
- NUMBER(p,s) -> numeric(p,s)
- VARCHAR2 -> varchar/text based on domain and indexing strategy
- DATE -> timestamp without time zone (if source stores time semantics)
- CLOB -> text
- BLOB -> bytea

Real-world caveats:
- NUMBER without precision in Oracle often needs explicit profiling before mapping.
- Date arithmetic and truncation semantics differ and can impact reports.
- Character-set and collation behavior can alter uniqueness and sort order.

## 4. Constraint and Index Strategy

- Create core tables first.
- Load data before enabling expensive FK validations when feasible.
- Rebuild indexes with dependency-aware sequencing.
- Validate uniqueness assumptions with pre-cutover profiling.

Index migration pitfalls:
- Function-based Oracle indexes may require generated columns or expression indexes.
- Over-indexing from source can hurt write throughput under CDC.

## 5. PL/SQL to PL/pgSQL Remediation

Approach:
- Prioritize business-critical package procedures and triggers.
- Replace autonomous transactions and Oracle-specific exception semantics carefully.
- Move non-essential procedural logic to application/service layer where practical.

Common incompatibilities:
- BULK COLLECT/FORALL patterns
- DBMS_SCHEDULER jobs
- Oracle package state behavior
- Dynamic SQL assumptions around synonyms and schema resolution

## 6. Sequence and Identity Handling

- Inventory all sequence-backed objects.
- Define ownership and restart behavior in PostgreSQL.
- During cutover, set sequence values to max(target_pk)+offset.
- Validate inserts from all application paths post-switch.

## 7. Object-Level Sign-off Matrix

Each object class should track:
- Conversion status
- Unit test status
- Integration test status
- Performance status
- Business owner sign-off

## Author

Author: Nitish Anand Srivastava
