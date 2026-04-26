# Shadow Table Migration Pattern

For large tables (>1TB), schema changes should be applied using shadow table techniques.

## Approach
- Create shadow table with new schema
- Sync data incrementally
- Switch traffic after validation

## Tools
- gh-ost
- pt-online-schema-change

## Benefits
- Minimal locking
- Reduced downtime
- Safer schema evolution
