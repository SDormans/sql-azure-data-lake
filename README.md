# Azure Data Lake with SQL Analytics — Portfolio Project

## Architecture Overview

This project demonstrates a **medallion architecture** data lake on Azure. Data flows from source systems through three zones in Azure Data Lake Storage (ADLS) Gen2 — **Raw**, **Processed**, and **Curated** — before serving analytics via Azure Synapse.

**Data flow diagram:**
```
[Source Systems]
     ↓  ADF ingestion
[ADLS Gen2 /raw]          CSV/JSON/Parquet landing
     ↓  Databricks ETL
[ADLS Gen2 /processed]    Cleaned, deduped, Parquet
     ↓  SQL / Spark
[ADLS Gen2 /curated]      Final aggregates for reporting
     ↓  External tables
[Azure Synapse Analytics] BI dashboards & ad-hoc queries
```

The project covers ingestion, storage governance, SQL transformation, and analytics delivery using realistic sales transaction and customer log data.

---

## Azure Services Used

| Service | Role |
|---------|------|
| **ADLS Gen2** | Unified storage with hierarchical namespace; hosts raw, processed, and curated zones. |
| **Azure Data Factory** | Orchestrates scheduled Copy activities from sources into the ADLS raw zone. |
| **Azure Databricks** | Spark ETL cleans raw data and writes Parquet to the processed zone. |
| **Azure Synapse Analytics** | Serverless SQL pool exposes external tables over Parquet; dedicated pool materializes curated aggregates. |
| **Azure SQL Database** (optional) | Alternative for structured staging before curated loads. |

---

## SQL Implementation

The SQL layer exposes raw data, loads staging tables, transforms for business logic, and powers reporting.

### 1. External Tables (Serverless Synapse)

External tables query Parquet in ADLS without loading into dedicated pools.

```sql
CREATE DATABASE SCOPED CREDENTIAL ADLSCredential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
     SECRET = '<SAS_TOKEN>';

CREATE EXTERNAL DATA SOURCE ProcessedADLS
WITH ( LOCATION = 'https://datalakeproject.dfs.core.windows.net/processed/',
       CREDENTIAL = ADLSCredential );

CREATE EXTERNAL FILE FORMAT ParquetFormat
WITH ( FORMAT_TYPE = PARQUET );

CREATE EXTERNAL TABLE ext.sales_transactions (
    transaction_id   INT,
    transaction_date DATE,
    customer_id      INT,
    product_id       INT,
    quantity         INT,
    unit_price       DECIMAL(10,2),
    region           VARCHAR(50)
)
WITH ( DATA_SOURCE = ProcessedADLS,
       LOCATION = 'sales_transactions/',
       FILE_FORMAT = ParquetFormat );
```

### 2. Load into Staging Tables

```sql
CREATE TABLE dbo.stg_sales (
    transaction_id   INT,
    transaction_date DATE,
    customer_id      INT,
    product_id       INT,
    quantity         INT,
    unit_price       DECIMAL(10,2),
    region           VARCHAR(50),
    loaded_at        DATETIME2 DEFAULT GETDATE()
);

INSERT INTO dbo.stg_sales
SELECT * FROM ext.sales_transactions;
```

### 3. Transform Data (Cleaning & Aggregation)

```sql
CREATE TABLE dbo.fact_sales AS
WITH deduped AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY transaction_date) AS rn
    FROM dbo.stg_sales
    WHERE quantity > 0 AND unit_price > 0
)
SELECT transaction_id, transaction_date, customer_id,
       product_id, quantity, unit_price, region
FROM deduped WHERE rn = 1;

CREATE TABLE dbo.daily_sales_summary AS
SELECT transaction_date, region,
       COUNT(*) AS transaction_count,
       SUM(quantity * unit_price) AS total_revenue,
       AVG(unit_price) AS avg_unit_price
FROM dbo.fact_sales
GROUP BY transaction_date, region;
```

### 4. Query Curated Data for Reporting

```sql
SELECT region,
       SUM(total_revenue) AS monthly_revenue,
       COUNT(transaction_count) AS total_transactions
FROM dbo.daily_sales_summary
WHERE transaction_date >= '2024-01-01'
  AND transaction_date <  '2024-02-01'
GROUP BY region
ORDER BY monthly_revenue DESC;
```

---

## Skills Demonstrated

- **Data Lake Design**: Medallion zones (bronze / silver / gold) with ADLS Gen2.
- **SQL Development**: External tables, PolyBase loading, CTEs, window functions, aggregation, dimensional modeling.
- **ETL Orchestration**: Understanding of ADF pipelines and Databricks for transformation workflows.
- **Cloud Data Services**: Synapse serverless vs. dedicated pools, ADLS Gen2 RBAC, end-to-end architecture.
- **Data Modeling**: Star-schema fact and dimension tables ready for Power BI or Tableau.

---

## How to Use This Project

1. Review the architecture diagram and data flow description.
2. Examine the SQL scripts in `sql/` in order (01 → 04).
3. Replace placeholder credentials and storage paths with your Azure values.
4. Execute in Azure Synapse Studio or SSMS connected to Synapse.
5. Connect Power BI or Tableau to the curated tables for dashboarding.
# sql-azure-data-lake
