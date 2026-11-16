-- ============================================
-- 02_load_to_staging.sql
-- PolyBase load into Staging (Dedicated SQL Pool)
-- ============================================

CREATE TABLE dbo.stg_sales (
    transaction_id   INT,
    transaction_date DATE,
    customer_id      INT,
    product_id       INT,
    quantity         INT,
    unit_price       DECIMAL(10,2),
    region           VARCHAR(50),
    loaded_at        DATETIME2 DEFAULT GETDATE()   -- carried over from /processed; watermark for 05
);

-- Initial full load. Recurring loads use 05_incremental_load.sql.
INSERT INTO dbo.stg_sales (transaction_id, transaction_date, customer_id,
                           product_id, quantity, unit_price, region, loaded_at)
SELECT transaction_id,
       transaction_date,
       customer_id,
       product_id,
       quantity,
       unit_price,
       region,
       loaded_at
FROM ext.sales_transactions;
