# Sample Datasets

Small sample files for trying out the pipeline end to end. The folder layout mirrors the **raw** zone of the lake (see [`docs/naming_conventions.md`](../docs/naming_conventions.md)), so `datasets/raw/` can be uploaded to the `raw` container as-is:

```
datasets/raw/
├── sales_transactions/
│   ├── load_date=2024-01-05/sales_transactions_20240105.csv
│   └── load_date=2024-01-06/sales_transactions_20240106.csv
└── customer_logs/
    ├── load_date=2024-01-05/customer_logs_20240105.json
    └── load_date=2024-01-06/customer_logs_20240106.json
```

Upload example (Azure CLI):

```bash
az storage fs directory upload \
  --account-name datalakeproject --file-system raw \
  --source "datasets/raw/*" --recursive --auth-mode login
```

Two `load_date` partitions are provided so the second day can be used to try the incremental load in [`sql/05_incremental_load.sql`](../sql/05_incremental_load.sql).

## `sales_transactions` (CSV, header row)

Columns match `ext.sales_transactions` in [`sql/01_create_external_tables.sql`](../sql/01_create_external_tables.sql) and `dbo.stg_sales` in [`sql/02_load_to_staging.sql`](../sql/02_load_to_staging.sql). `loaded_at` is not part of the source export: the Databricks job adds it when writing the row to the `processed` zone.

| Column | Type | Notes |
|--------|------|-------|
| `transaction_id` | `INT` | Business key |
| `transaction_date` | `DATE` | `YYYY-MM-DD` |
| `customer_id` | `INT` | |
| `product_id` | `INT` | |
| `quantity` | `INT` | |
| `unit_price` | `DECIMAL(10,2)` | |
| `region` | `VARCHAR(50)` | `North`, `South`, `East`, `West` |

## `customer_logs` (JSON Lines, one event per line)

| Field | Type | Notes |
|-------|------|-------|
| `log_id` | `INT` | Business key |
| `customer_id` | `INT` | |
| `event_timestamp` | `DATETIME2` | `YYYY-MM-DD HH:MM:SS` |
| `event_type` | `VARCHAR(50)` | `page_view`, `add_to_cart`, `purchase` |
| `page_visited` | `VARCHAR(200)` | |
| `device` | `VARCHAR(20)` | `Mobile`, `Desktop`, `Tablet` |

## Known data quality issues (intentional)

The raw zone stores data as received, so the samples contain a few bad records for the raw-zone checks in [`tests/quality_checks.sql`](../tests/quality_checks.sql) to find. They must be removed before data reaches `processed`.

| File | Record | Issue |
|------|--------|-------|
| `sales_transactions_20240105.csv` | `transaction_id = 1008` | Negative `quantity` |
| `sales_transactions_20240106.csv` | `transaction_id = 1010` | `NULL` `customer_id` |
| `sales_transactions_20240106.csv` | `transaction_id = 1011` | Negative `unit_price` |
| `sales_transactions_20240106.csv` | `transaction_id = 1007` | Duplicate (resend of the 2024-01-05 record) |
| `sales_transactions_20240106.csv` | Last row | `NULL` `transaction_id` |
| `customer_logs_20240105.json` | `log_id = 2006` | `NULL` `customer_id` |
| `customer_logs_20240106.json` | `log_id = 2005` | Duplicate (resend of the 2024-01-05 event) |
