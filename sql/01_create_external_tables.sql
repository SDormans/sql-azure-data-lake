-- ============================================
-- 01_create_external_tables.sql
-- Azure Synapse Serverless - External Tables
-- ============================================

CREATE DATABASE SCOPED CREDENTIAL ADLSCredential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
     SECRET = '<REPLACE_WITH_SAS_TOKEN>';

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
