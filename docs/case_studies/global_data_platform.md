# Case Study: Global Data Platform (HA/DR + Medallion)

## Problem
A global retail system required near real-time analytics across regions with strict uptime requirements (99.99%). Existing system suffered from high latency and fragile pipelines.

## Architecture
- Ingestion: dlt pipelines (API + batch)
- Storage: Bronze/Silver/Gold (dbt models)
- Database: PostgreSQL (primary + replicas)
- Analytics: Gold layer tables
- Infra: Terraform (multi-AZ), Kubernetes (optional workloads)
- Observability: freshness + schema drift checks

## Key Decisions
- Adopt Medallion architecture for separation of concerns
- Use Parquet/Delta for efficient analytics
- Implement read replicas for scaling
- Introduce data contracts for reliability

## Trade-offs
- Slight increase in storage cost for layered data
- Added complexity in orchestration

## Results
- Query latency reduced from ~4.5s to ~1.3s (≈70% improvement)
- Pipeline reliability improved (fewer failures, automated validation)
- Cost optimized by ~35% via storage format tuning and infra automation

## Lessons Learned
- Data contracts significantly reduce downstream issues
- Observability is as important as pipeline logic
- Architecture matters more than individual tools
