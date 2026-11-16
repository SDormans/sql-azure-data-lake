/*
===============================================================================
Quality Checks
===============================================================================
Script Purpose:
    This script performs quality checks for data consistency and accuracy
    across every zone of the data lake. It includes checks for:
    - Null or duplicate business keys (transaction_id, log_id).
    - Negative or zero quantity / unit_price.
    - Watermark consistency for the incremental staging load.
    - Reconciliation between curated aggregates and the fact table.

Usage Notes:
    - Raw and Processed checks query the lake directly and run on the
      Synapse serverless SQL pool (raw checks use OPENROWSET over the
      RawADLS data source from sql/01_create_external_tables.sql).
    - Staging and Curated checks run on the dedicated SQL pool after
      sql/02 (or sql/05) and sql/03 have run.
    - The raw zone stores data as received, so its checks are expected to
      return the issues listed in datasets/README.md; every other check
      should return no results.
    - Investigate and resolve any discrepancies found during the checks.
===============================================================================
*/

-- ====================================================================
-- Raw zone: 'raw/sales_transactions' (CSV)
-- ====================================================================
-- Check for NULLs or Duplicates in Business Key
-- Expectation: Only the known issues in datasets/README.md
SELECT 
    transaction_id,
    COUNT(*) AS record_count
FROM OPENROWSET(
        BULK 'sales_transactions/load_date=*/*.csv',
        DATA_SOURCE = 'RawADLS',
        FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE
     ) WITH (
        transaction_id   INT,
        transaction_date DATE,
        customer_id      INT,
        product_id       INT,
        quantity         INT,
        unit_price       DECIMAL(10,2),
        region           VARCHAR(50)
     ) AS raw_sales
GROUP BY transaction_id
HAVING COUNT(*) > 1 OR transaction_id IS NULL;

-- Check for NULL Keys and Negative or Zero Quantity / Unit Price
-- Expectation: Only the known issues in datasets/README.md
SELECT 
    raw_sales.filepath(1) AS load_date,
    *
FROM OPENROWSET(
        BULK 'sales_transactions/load_date=*/*.csv',
        DATA_SOURCE = 'RawADLS',
        FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE
     ) WITH (
        transaction_id   INT,
        transaction_date DATE,
        customer_id      INT,
        product_id       INT,
        quantity         INT,
        unit_price       DECIMAL(10,2),
        region           VARCHAR(50)
     ) AS raw_sales
WHERE transaction_id IS NULL
   OR transaction_date IS NULL
   OR customer_id IS NULL
   OR product_id IS NULL
   OR quantity <= 0
   OR unit_price <= 0;

-- ====================================================================
-- Raw zone: 'raw/customer_logs' (JSON Lines)
-- ====================================================================
-- Check for NULLs or Duplicates in Business Key
-- Expectation: Only the known issues in datasets/README.md
SELECT 
    CAST(JSON_VALUE(doc, '$.log_id') AS INT) AS log_id,
    COUNT(*)                                 AS record_count
FROM OPENROWSET(
        BULK 'customer_logs/load_date=*/*.json',
        DATA_SOURCE = 'RawADLS',
        FORMAT = 'CSV', FIELDTERMINATOR = '0x0b', FIELDQUOTE = '0x0b', ROWTERMINATOR = '0x0a'
     ) WITH (doc NVARCHAR(MAX)) AS raw_logs
GROUP BY CAST(JSON_VALUE(doc, '$.log_id') AS INT)
HAVING COUNT(*) > 1 OR CAST(JSON_VALUE(doc, '$.log_id') AS INT) IS NULL;

-- Check for NULL Keys
-- Expectation: Only the known issues in datasets/README.md
SELECT 
    raw_logs.filepath(1) AS load_date,
    doc
FROM OPENROWSET(
        BULK 'customer_logs/load_date=*/*.json',
        DATA_SOURCE = 'RawADLS',
        FORMAT = 'CSV', FIELDTERMINATOR = '0x0b', FIELDQUOTE = '0x0b', ROWTERMINATOR = '0x0a'
     ) WITH (doc NVARCHAR(MAX)) AS raw_logs
WHERE JSON_VALUE(doc, '$.log_id') IS NULL
   OR JSON_VALUE(doc, '$.customer_id') IS NULL
   OR JSON_VALUE(doc, '$.event_timestamp') IS NULL;

-- Data Standardization & Consistency
SELECT DISTINCT 
    JSON_VALUE(doc, '$.event_type') AS event_type,
    JSON_VALUE(doc, '$.device')     AS device
FROM OPENROWSET(
        BULK 'customer_logs/load_date=*/*.json',
        DATA_SOURCE = 'RawADLS',
        FORMAT = 'CSV', FIELDTERMINATOR = '0x0b', FIELDQUOTE = '0x0b', ROWTERMINATOR = '0x0a'
     ) WITH (doc NVARCHAR(MAX)) AS raw_logs;

-- ====================================================================
-- Processed zone: 'ext.sales_transactions' (Parquet)
-- ====================================================================
-- Check for NULLs or Duplicates in Business Key
-- Expectation: No Results
SELECT 
    transaction_id,
    COUNT(*) AS record_count
FROM ext.sales_transactions
GROUP BY transaction_id
HAVING COUNT(*) > 1 OR transaction_id IS NULL;

-- Check for NULL Keys
-- Expectation: No Results
SELECT 
    *
FROM ext.sales_transactions
WHERE transaction_date IS NULL
   OR customer_id IS NULL
   OR product_id IS NULL
   OR loaded_at IS NULL;

-- Check for NULLs, Negative or Zero Quantity / Unit Price
-- Expectation: No Results
SELECT 
    *
FROM ext.sales_transactions
WHERE quantity IS NULL
   OR unit_price IS NULL
   OR quantity <= 0
   OR unit_price <= 0;

-- Data Standardization & Consistency
SELECT DISTINCT 
    region
FROM ext.sales_transactions;

-- ====================================================================
-- Staging: 'dbo.stg_sales'
-- ====================================================================
-- Check for NULLs or Duplicates in Business Key
-- (duplicates usually mean a window was loaded twice, e.g. 02 re-run after 05)
-- Expectation: No Results
SELECT 
    transaction_id,
    COUNT(*) AS record_count
FROM dbo.stg_sales
GROUP BY transaction_id
HAVING COUNT(*) > 1 OR transaction_id IS NULL;

-- Check for NULL Keys
-- Expectation: No Results
SELECT 
    *
FROM dbo.stg_sales
WHERE transaction_date IS NULL
   OR customer_id IS NULL
   OR product_id IS NULL
   OR loaded_at IS NULL;

-- Check for NULLs, Negative or Zero Quantity / Unit Price
-- Expectation: No Results
SELECT 
    *
FROM dbo.stg_sales
WHERE quantity IS NULL
   OR unit_price IS NULL
   OR quantity <= 0
   OR unit_price <= 0;

-- Check Watermark Consistency (skip if sql/05 has not run yet)
-- Expectation: No Results
SELECT 
    s.*,
    w.watermark_value
FROM dbo.stg_sales s
CROSS JOIN dbo.etl_watermark w
WHERE w.table_name = 'dbo.stg_sales'
  AND s.loaded_at > w.watermark_value;

-- ====================================================================
-- Curated: 'dbo.fact_sales'
-- ====================================================================
-- Check for NULLs or Duplicates in Business Key
-- Expectation: No Results
SELECT 
    transaction_id,
    COUNT(*) AS record_count
FROM dbo.fact_sales
GROUP BY transaction_id
HAVING COUNT(*) > 1 OR transaction_id IS NULL;

-- Check for NULL Keys
-- Expectation: No Results
SELECT 
    *
FROM dbo.fact_sales
WHERE transaction_date IS NULL
   OR customer_id IS NULL
   OR product_id IS NULL;

-- Check for NULLs, Negative or Zero Quantity / Unit Price
-- Expectation: No Results
SELECT 
    *
FROM dbo.fact_sales
WHERE quantity IS NULL
   OR unit_price IS NULL
   OR quantity <= 0
   OR unit_price <= 0;

-- ====================================================================
-- Curated: 'dbo.daily_sales_summary'
-- ====================================================================
-- Check for NULLs or Duplicates in Grain (transaction_date, region)
-- Expectation: No Results
SELECT 
    transaction_date,
    region,
    COUNT(*) AS record_count
FROM dbo.daily_sales_summary
GROUP BY transaction_date, region
HAVING COUNT(*) > 1 OR transaction_date IS NULL;

-- Check Data Consistency: Summary reconciles with dbo.fact_sales
-- Expectation: No Results
SELECT 
    COALESCE(s.transaction_date, f.transaction_date) AS transaction_date,
    COALESCE(s.region, f.region)                     AS region,
    s.transaction_count                              AS summary_count,
    f.transaction_count                              AS fact_count,
    s.total_revenue                                  AS summary_revenue,
    f.total_revenue                                  AS fact_revenue
FROM dbo.daily_sales_summary s
FULL OUTER JOIN (
    SELECT 
        transaction_date,
        region,
        COUNT(*)                   AS transaction_count,
        SUM(quantity * unit_price) AS total_revenue
    FROM dbo.fact_sales
    GROUP BY transaction_date, region
) f
    ON  s.transaction_date = f.transaction_date
    AND (s.region = f.region OR (s.region IS NULL AND f.region IS NULL))
WHERE s.transaction_date IS NULL
   OR f.transaction_date IS NULL
   OR s.transaction_count != f.transaction_count
   OR s.total_revenue != f.total_revenue;
