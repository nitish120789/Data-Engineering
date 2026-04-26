# Storage Format Benchmarks

Dataset: 10M rows synthetic retail dataset
Engine: DuckDB

## Results

| Format  | Query Time (s) | Storage Size | Notes |
|---------|-----------------|--------------|-------|
| Parquet | 1.2             | 1.0x         | Columnar, efficient scans |
| Avro    | 2.0             | 1.3x         | Row-based, larger footprint |
| Delta   | 1.3             | 1.1x         | ACID + optimized reads |
| Iceberg | 1.4             | 1.1x         | Schema evolution friendly |

## Takeaways
- Parquet/Delta provide fastest analytical queries
- Avro is better for write-heavy pipelines
- Iceberg/Delta add governance and evolution features
