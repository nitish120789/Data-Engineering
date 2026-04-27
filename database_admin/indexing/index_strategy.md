# Index Strategy Guide

**For comprehensive index lifecycle management (creation, monitoring, maintenance, removal), see**:

[Index Lifecycle Management Guide](index-lifecycle-management.md)

That guide covers:

- Index proposal and cost-benefit analysis
- Safe creation procedures (concurrent vs. blocking) by engine
- Ongoing monitoring and health checks
- Obsolescence detection (unused, redundant, poor selectivity)
- Safe removal procedures and rollback
- Best practices and automation opportunities

## Quick Index Decision Matrix

| Scenario | Decision | Details |
|---|---|---|
| Query doing full table scan on 1M+ row table | Create index | If index filters to <5% of rows and query runs >100x/day |
| Index unused for 90 days | Remove | Unless it's for rare emergency case or slow backup query |
| Two indexes on same leading column | Consolidate | Keep more selective one; remove redundant |
| Index on low-cardinality column (e.g., status with 3 values) | Consider partial index instead | Partial indexes are much smaller and faster to maintain |
| Application INSERT/UPDATE getting slower after index creation | Review write penalty | If >5%, reconsider index design or use partial index |

See the full [Index Lifecycle Management Guide](index-lifecycle-management.md) for commands, monitoring queries, and quarterly review procedures.
