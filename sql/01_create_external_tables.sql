-- ============================================
-- 01_create_external_tables.sql
-- Azure Synapse Serverless - External Tables
-- ============================================

IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<REPLACE_WITH_STRONG_PASSWORD>';

CREATE DATABASE SCOPED CREDENTIAL ADLSCredential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
     SECRET = '<REPLACE_WITH_SAS_TOKEN>';

CREATE EXTERNAL DATA SOURCE RawADLS
WITH ( LOCATION = 'https://datalakeproject.dfs.core.windows.net/raw/',
       CREDENTIAL = ADLSCredential );

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
