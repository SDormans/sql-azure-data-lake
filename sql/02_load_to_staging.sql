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
    loaded_at        DATETIME2 DEFAULT GETDATE()
);

INSERT INTO dbo.stg_sales
SELECT *
FROM ext.sales_transactions;
