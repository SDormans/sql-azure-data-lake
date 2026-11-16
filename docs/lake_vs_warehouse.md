# Data Lake vs. Data Warehouse

This project (**sql-azure-data-lake**) and its companion [**sql-data-warehouse**](https://github.com/SDormans/sql-data-warehouse) both implement a medallion architecture for sales analytics, but on very different platforms. This page compares the two and explains when each approach fits.

| | sql-azure-data-lake (this repo) | sql-data-warehouse |
|---|---|---|
| **Medallion tiers** | Raw → Processed → Curated | Bronze → Silver → Gold |
| **Sources** | Sales transactions (CSV) and customer event logs (JSON) | CRM and ERP exports (CSV) |
| **Orchestration** | Azure Data Factory pipelines | Stored procedures run manually (`EXEC bronze.load_bronze_crm`, …) |
| **Load strategy** | Initial full load (`sql/02`), then incremental by `loaded_at` watermark (`sql/05`) | Full load (truncate & insert) for Bronze and Silver |
| **Quality checks** | `tests/quality_checks.sql`, one section per zone | `tests/quality_checks_silver.sql`, `tests/quality_checks_gold.sql` |

## Platform

| sql-azure-data-lake | sql-data-warehouse |
|---|---|
| Fully managed Azure services: **ADLS Gen2** for storage, **Data Factory** for ingestion, **Databricks** for Spark ETL, **Synapse Analytics** (serverless and dedicated SQL pools) for SQL. | A single **SQL Server** instance (2017 or later, Express/Developer is enough), on-premises or on a VM, managed with SSMS. |
| Each component scales independently and is provisioned in the cloud. | One engine does storage, transformation and serving; scaling means a bigger server. |

## Storage model: schema-on-read vs. schema-on-write

| sql-azure-data-lake — **schema-on-read** | sql-data-warehouse — **schema-on-write** |
|---|---|
| Files land in the lake as they are (CSV, JSON) and are converted to Parquet; the schema is applied when the data is **queried**, through `OPENROWSET` or external tables such as `ext.sales_transactions`. | Data is loaded into typed tables (`bronze.*`, `silver.*`) with a fixed schema; it must fit the table definition **before** it is stored. |
| Bad or unexpected data still lands (and is caught later by the raw-zone checks), so nothing is lost at ingestion and new sources can be added without upfront modeling. | Type mismatches fail the `BULK INSERT`, so problems surface at load time and every stored row conforms to the schema. |
| Semi-structured data (JSON event logs) is stored natively. | Built for structured, tabular data. |
| Storage is decoupled from compute: the same files can be read by Spark, Synapse or other tools. | Storage is tied to the SQL Server database. |

## Transform engine

| sql-azure-data-lake | sql-data-warehouse |
|---|---|
| **Apache Spark on Databricks** cleans and deduplicates raw files into Parquet (raw → processed). **Synapse SQL** loads staging and builds curated tables with `CREATE TABLE AS SELECT` (`sql/03`). | **T-SQL stored procedures** (`bronze.load_bronze_*`, `silver.load_silver`) inside SQL Server. |
| Distributed: work is spread over a cluster or the dedicated pool's distributions. | Single-node, set-based T-SQL. |
| Python/Scala/SQL can be mixed, which suits large volumes and complex parsing. | Everything is plain SQL, which is simpler to develop, debug and review. |

## Serving layer

| sql-azure-data-lake | sql-data-warehouse |
|---|---|
| **Synapse**: the serverless SQL pool queries lake files ad hoc through external tables; the dedicated SQL pool serves materialized curated tables (`dbo.fact_sales`, `dbo.daily_sales_summary`) to BI tools. | **Gold views** (`gold.dim_customers`, `gold.dim_products`, `gold.fact_sales`) in the same SQL Server database, computed on read from Silver. |
| Curated data is pre-aggregated for dashboard performance. | Star schema is always current with Silver; no separate refresh step. |
| Power BI/Tableau connect to the Synapse SQL endpoint. | Power BI/Tableau connect directly to SQL Server. |

## Cost model

| sql-azure-data-lake — **pay per use** | sql-data-warehouse — **fixed** |
|---|---|
| **ADLS Gen2**: billed per GB stored and per storage transaction; very cheap for large volumes. | **SQL Server license**: free for Express/Developer; Standard/Enterprise are licensed per core (or server + CAL). |
| **Synapse serverless**: billed per TB of data **processed** by each query, so Parquet, partition pruning and narrow `SELECT`s directly reduce cost. | **Hardware / VM**: the server costs the same whether it is busy or idle. |
| **Synapse dedicated pool**: billed per hour by provisioned DWU; can be paused when idle. | No per-query cost; heavier workloads mean buying a bigger machine. |
| **Databricks**: billed per DBU plus the underlying VMs while clusters run. **Data Factory**: billed per activity run and data movement. | Operational cost is mainly the people maintaining the server (patching, backups). |
| Scales to zero, but costs grow with usage and need monitoring (budgets, auto-pause, auto-terminate). | Predictable, but capacity must be sized for peak load. |

## When to use which

**Choose the data lake approach when:**

- Data volumes are large (hundreds of GB and up) or growing fast.
- Sources are varied or semi-structured (JSON logs, events, files from many systems), or schemas change often.
- Raw data must be kept cheaply and in full for reprocessing, auditing or data science/ML.
- Several engines (Spark, SQL, ML tools) need to share the same data.
- Workloads are bursty and pay-per-use is cheaper than an always-on server.
- The organization is already on Azure and wants managed services.

**Choose the SQL Server warehouse approach when:**

- Data is structured and modest in size (fits comfortably on one server).
- Sources are a few well-known systems (e.g. CRM and ERP) with stable schemas.
- The team's skills are mainly T-SQL, and simplicity matters more than scale.
- Strong typing and constraints at load time are preferred over flexibility.
- Data must stay on-premises, or a predictable fixed cost is required.
- Reporting needs a single, always-consistent star schema with minimal moving parts.

**Combine them** when both apply: use the lake for cheap, flexible raw/processed storage and heavy Spark transformations, and load the curated, modeled subset into a warehouse (Synapse dedicated pool or SQL Server) for governed BI reporting — which is essentially the pattern this repository's curated layer follows.
