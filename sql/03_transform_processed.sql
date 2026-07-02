-- ============================================
-- 03_transform_processed.sql
-- Cleansing and Aggregation — Curated Layer
-- ============================================

CREATE TABLE dbo.fact_sales AS
WITH deduped AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY transaction_date) AS rn
    FROM dbo.stg_sales
    WHERE quantity > 0
      AND unit_price > 0
)
SELECT transaction_id,
       transaction_date,
       customer_id,
       product_id,
       quantity,
       unit_price,
       region
FROM deduped
WHERE rn = 1;

CREATE TABLE dbo.daily_sales_summary AS
SELECT transaction_date,
       region,
       COUNT(*)                   AS transaction_count,
       SUM(quantity * unit_price)  AS total_revenue,
       AVG(unit_price)             AS avg_unit_price
FROM dbo.fact_sales
GROUP BY transaction_date, region;
