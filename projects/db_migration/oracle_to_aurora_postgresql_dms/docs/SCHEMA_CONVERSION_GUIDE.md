# Schema Conversion Guide
## Oracle to Amazon Aurora PostgreSQL

## Purpose

This guide covers the practical schema conversion path for Oracle to Aurora PostgreSQL and highlights the most common issues that appear after automated conversion.

## Recommended Tooling

Primary tool:
- ora2pg for assessment and first-pass schema conversion

Supporting tools:
- SQL Developer / DBMS_METADATA for DDL extraction review
- psql for target deployment validation
- EXPLAIN / EXPLAIN ANALYZE for query-plan verification after conversion

## Conversion Workflow

1. Extract source DDL and object inventory.
2. Run ora2pg SHOW_REPORT to estimate conversion effort.
3. Export tables, views, sequences, functions, and packages separately.
4. Review generated output and normalize naming conventions.
5. Patch incompatible constructs manually.
6. Deploy to Aurora lower environment.
7. Run validation queries and representative application tests.

## Common Oracle to PostgreSQL Mappings

- NUMBER(p,0) -> integer or bigint when safe
- NUMBER(p,s) -> numeric(p,s)
- VARCHAR2 -> varchar or text
- DATE -> timestamp without time zone when time component matters
- CLOB -> text
- BLOB -> bytea
- RAW -> bytea

## Known Issues and Fixes

### 1. NUMBER without precision

Problem:
- Oracle allows NUMBER without precision, but PostgreSQL requires more explicit intent.

Fix:
- profile max and min values in Oracle before choosing bigint or numeric.
- avoid defaulting large business keys to numeric unless required.

### 2. Empty string versus NULL

Problem:
- Oracle treats empty string as NULL in many contexts; PostgreSQL does not.

Fix:
- identify code paths relying on this behavior.
- rewrite predicates and data-cleansing rules explicitly.

### 3. Oracle DATE semantics

Problem:
- Oracle DATE stores date and time; PostgreSQL date does not.

Fix:
- use timestamp for columns where time is semantically relevant.
- review reporting SQL for truncation and timezone assumptions.

### 4. Packages, package state, autonomous transactions

Problem:
- Aurora PostgreSQL has no direct equivalent for package state or autonomous transactions.

Fix:
- split package routines into standalone functions.
- move transactional side effects into application/service workflows where needed.

### 5. Synonyms and DB links

Problem:
- Oracle synonyms and DB links can hide cross-schema and cross-database dependencies.

Fix:
- replace with explicit schema qualification and application-managed integrations.

### 6. Function-based indexes

Problem:
- Oracle function-based indexes often convert poorly if functions or expressions differ.

Fix:
- create PostgreSQL expression indexes or generated columns where appropriate.

### 7. Sequences and identity columns

Problem:
- DMS does not always align target sequences after data load.

Fix:
- inventory sequence ownership and run scripts/sequence_reseed.sql before go-live.

## Sign-Off Criteria

- all critical tables and indexes created
- all critical routines remediated or redesign approved
- no unresolved datatype ambiguity on critical columns
- query-plan review completed for top application SQL

## Author

Author: Nitish Anand Srivastava
