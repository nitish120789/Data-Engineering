# Azure Data Box Workflow

## Steps
1. Export data from SQL Server into CSV/Parquet
2. Load data into Azure Data Box
3. Ship Data Box to Azure region
4. Ingest into Azure Blob Storage
5. Load into Azure SQL using Data Factory

## Notes
- Use compression to reduce transfer size
- Validate checksum after ingestion
