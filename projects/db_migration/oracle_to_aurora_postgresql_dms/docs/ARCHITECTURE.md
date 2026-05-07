# Architecture
## Oracle to Amazon Aurora PostgreSQL Migration with AWS DMS

## Reference Topology

```text
On-Premises
+------------------------------------------------------------+
| Oracle Primary                                             |
|  - ARCHIVELOG enabled                                      |
|  - Supplemental logging enabled                            |
|  - Application writes continue during migration            |
+--------------------------+---------------------------------+
                           |
                           | Oracle endpoint over VPN / DX
                           v
AWS
+------------------------------------------------------------+
| AWS DMS Replication Instance                               |
|  - Full load from Oracle to Aurora PostgreSQL              |
|  - CDC from Oracle redo/archive logs                       |
|  - Table mappings and task settings                        |
+--------------------------+---------------------------------+
                           |
                           v
+------------------------------------------------------------+
| Amazon Aurora PostgreSQL                                   |
|  - Pre-created target schema                               |
|  - Full load target                                        |
|  - CDC apply target                                        |
|  - Validation schema / checkpoint tables                   |
+------------------------------------------------------------+
```

## Why AWS DMS Fits a 100 GB Migration

For a 100 GB Oracle database, AWS DMS is usually sufficient for both initial full load and CDC without introducing additional bulk-transfer tooling. The main engineering effort shifts to schema conversion, task tuning, and validation discipline.

## Migration Stages

### Stage 1: Discovery and conversion preparation

- Inventory object types, schemas, LOBs, invalid objects, and non-default NLS settings.
- Identify Oracle-specific features that will not translate directly.
- Size the DMS replication instance based on peak change volume, not only database size.

### Stage 2: Schema conversion

- Extract DDL from Oracle.
- Run ora2pg for first-pass conversion.
- Manually remediate procedural code, datatypes, indexes, and constraints.
- Apply schema to Aurora before data movement.

### Stage 3: Full load

- Launch AWS DMS task in full-load-and-cdc mode.
- Load base tables in dependency-aware order.
- Defer or carefully sequence FK validation and heavy indexes where needed.

### Stage 4: CDC catch-up

- Continue applying source changes while application remains online.
- Monitor source latency, target latency, task logs, and table-level errors.
- Prevent in-scope DDL changes after task start.

### Stage 5: Validation and cutover

- Run reconciliation queries on Oracle and Aurora.
- Freeze source writes.
- Drain CDC to near-zero latency.
- Run final business and technical checks.
- Switch application connectivity.

## Real-World Failure Modes

- DMS full load completes, but CDC silently excludes unsupported DDL-driven changes.
- Package logic migrated incompletely, leading to application behavior drift.
- Sequence values lag behind target max keys after full load.
- Tables without PKs generate non-deterministic update/delete behavior.
- LOB columns require more aggressive DMS tuning than default settings.
- NLS date and timestamp semantics differ from Aurora query behavior.

## Operational Roles

- Oracle DBA: source logging, privileges, SCN/redo readiness, freeze execution
- PostgreSQL DBA: Aurora schema, indexing, parameter review, sequence and performance validation
- Migration Engineer: ora2pg conversion, DMS task configuration, log review
- Application Owner: smoke tests and business sign-off
- Change Manager: cutover gate and rollback governance

## Non-Functional Requirements

- Network path stable enough for continuous CDC
- Aurora sized for load plus replay overhead
- Encryption in transit and at rest
- Audit evidence retained for schema, task, and cutover decisions

## Author

Author: Nitish Anand Srivastava
