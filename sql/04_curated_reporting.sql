-- ============================================
-- 04_curated_reporting.sql
-- Reporting Queries on Curated Data
-- ============================================

SELECT region,
       SUM(total_revenue)        AS monthly_revenue,
       COUNT(transaction_count)   AS total_transactions
FROM dbo.daily_sales_summary
WHERE transaction_date >= '2024-01-01'
  AND transaction_date <  '2024-02-01'
GROUP BY region
ORDER BY monthly_revenue DESC;

SELECT f.transaction_date,
       p.product_name,
       SUM(f.quantity * f.unit_price) AS revenue
FROM dbo.fact_sales f
JOIN dbo.dim_product p ON f.product_id = p.product_id
WHERE f.transaction_date >= DATEADD(month, -3, GETDATE())
GROUP BY f.transaction_date, p.product_name
ORDER BY f.transaction_date, revenue DESC;
