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

## Repository Structure

```
sql-azure-data-lake/
├── datasets/
│   ├── README.md                    # Schemas and intentional data quality issues of the samples
│   └── raw/                         # Sample files laid out like the raw zone
│       ├── sales_transactions/      # load_date=YYYY-MM-DD/sales_transactions_YYYYMMDD.csv
│       └── customer_logs/           # load_date=YYYY-MM-DD/customer_logs_YYYYMMDD.json (JSON Lines)
├── diagrams/
│   └── architecture.mmd             # Pipeline flow diagram (Mermaid)
├── docs/
│   ├── naming_conventions.md        # Zone, folder, file, external table and table naming
│   └── lake_vs_warehouse.md         # Comparison with SDormans/sql-data-warehouse
├── sql/
│   ├── 01_create_external_tables.sql
│   ├── 02_load_to_staging.sql       # Initial full load into dbo.stg_sales
│   ├── 03_transform_processed.sql
│   ├── 04_curated_reporting.sql
│   └── 05_incremental_load.sql      # Watermark-based incremental load into dbo.stg_sales
├── tests/
│   └── quality_checks.sql           # Data quality checks per zone
└── README.md
```

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
    region           VARCHAR(50),
    loaded_at        DATETIME2       -- set by Databricks when the row is written to /processed
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

INSERT INTO dbo.stg_sales (transaction_id, transaction_date, customer_id,
                           product_id, quantity, unit_price, region, loaded_at)
SELECT transaction_id, transaction_date, customer_id,
       product_id, quantity, unit_price, region, loaded_at
FROM ext.sales_transactions;
```

### 2b. Incremental Load (Watermark)

After the initial full load, `sql/05_incremental_load.sql` appends only new rows instead of reloading everything. The highest `loaded_at` copied so far is kept in `dbo.etl_watermark`, and each run loads the window between that watermark and the latest `loaded_at` in the processed zone:

```sql
SET @old_watermark = (SELECT watermark_value FROM dbo.etl_watermark
                      WHERE table_name = 'dbo.stg_sales');
SET @new_watermark = (SELECT MAX(loaded_at) FROM ext.sales_transactions
                      WHERE loaded_at > @old_watermark);

INSERT INTO dbo.stg_sales (...)
SELECT ... FROM ext.sales_transactions
WHERE loaded_at > @old_watermark AND loaded_at <= @new_watermark;

UPDATE dbo.etl_watermark SET watermark_value = @new_watermark, updated_at = GETDATE()
WHERE table_name = 'dbo.stg_sales';
```

The window is deleted before it is inserted and the watermark only advances after the insert, so a failed run can safely be re-run. Runs must not overlap (set the ADF pipeline concurrency to 1).

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

## Sample Datasets

[`datasets/`](datasets/) contains small sample files whose folder layout mirrors the raw zone, so `datasets/raw/` can be uploaded to the `raw` container as-is:

- `sales_transactions` (CSV): same columns as `ext.sales_transactions` / `dbo.stg_sales` (without `loaded_at`, which Databricks adds).
- `customer_logs` (JSON Lines): customer web events (`page_view`, `add_to_cart`, `purchase`).

Two load dates are included to try the incremental load, and a few bad records (duplicates, negative values, `NULL` keys) are included on purpose for the quality checks. See [`datasets/README.md`](datasets/README.md) for the schemas and the list of known issues.

---

## Data Quality Checks

[`tests/quality_checks.sql`](tests/quality_checks.sql) checks every zone for duplicate `transaction_id`s / `log_id`s, negative or zero `quantity` / `unit_price`, and `NULL` keys, plus watermark consistency in staging and reconciliation between `dbo.daily_sales_summary` and `dbo.fact_sales`.

| Section | Object(s) | Run on |
|---------|-----------|--------|
| Raw zone | `raw/sales_transactions`, `raw/customer_logs` via `OPENROWSET` | Serverless SQL pool |
| Processed zone | `ext.sales_transactions` | Serverless SQL pool |
| Staging | `dbo.stg_sales` | Dedicated SQL pool |
| Curated | `dbo.fact_sales`, `dbo.daily_sales_summary` | Dedicated SQL pool |

Each check documents its expectation in a comment. Checks marked *Expectation: No Results* should return zero rows; raw-zone checks are expected to return only the known issues listed in `datasets/README.md`.

---

## Documentation

- [`docs/naming_conventions.md`](docs/naming_conventions.md) — naming rules for zones (containers), folders, files, external data sources/file formats/tables, Synapse tables, columns and scripts.
- [`docs/lake_vs_warehouse.md`](docs/lake_vs_warehouse.md) — how this project compares to [SDormans/sql-data-warehouse](https://github.com/SDormans/sql-data-warehouse) in platform, storage model (schema-on-read vs. schema-on-write), transform engine, serving layer and cost model, and when to use which.

---

## Skills Demonstrated

- **Data Lake Design**: Medallion zones (bronze / silver / gold) with ADLS Gen2.
- **SQL Development**: External tables, PolyBase loading, watermark-based incremental loads, CTEs, window functions, aggregation, dimensional modeling.
- **Data Quality**: Per-zone checks for duplicates, invalid values, `NULL` keys and aggregate reconciliation.
- **ETL Orchestration**: Understanding of ADF pipelines and Databricks for transformation workflows.
- **Cloud Data Services**: Synapse serverless vs. dedicated pools, ADLS Gen2 RBAC, end-to-end architecture.
- **Data Modeling**: Star-schema fact and dimension tables ready for Power BI or Tableau.

---

## How to Use This Project

1. Review the architecture diagram, data flow description and [`docs/naming_conventions.md`](docs/naming_conventions.md).
2. Upload `datasets/raw/` to the `raw` container of your ADLS Gen2 account (see [`datasets/README.md`](datasets/README.md)).
3. Replace placeholder credentials and storage paths in `sql/01_create_external_tables.sql` with your Azure values.
4. Execute the SQL scripts in `sql/` in order (01 → 04) in Azure Synapse Studio or SSMS connected to Synapse.
5. For subsequent loads, run `sql/05_incremental_load.sql` instead of `sql/02_load_to_staging.sql`, then re-run `sql/03_transform_processed.sql`.
6. Run `tests/quality_checks.sql` to validate each zone.
7. Connect Power BI or Tableau to the curated tables for dashboarding.
# sql-azure-data-lake
