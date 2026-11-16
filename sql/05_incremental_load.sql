-- ============================================
-- 05_incremental_load.sql
-- Incremental load into Staging using a loaded_at watermark (Dedicated SQL Pool)
-- ============================================
-- Replaces the full reload in 02 for recurring runs: only rows that landed in
-- the processed zone since the last successful run are appended to dbo.stg_sales.
--
--   1. dbo.etl_watermark stores the highest loaded_at copied per target table.
--   2. Each run loads the window (old watermark, MAX(loaded_at) in the source].
--      The upper bound is fixed up front, so rows written during the run are
--      picked up next time instead of being skipped.
--   3. The window is deleted before it is inserted and the watermark is only
--      advanced afterwards, so a failed run can simply be re-run.
--
-- Prerequisites: 01 and 02 have run (02 performs the initial full load).
-- Concurrency:   run one load at a time (e.g. ADF pipeline concurrency = 1).
--                Overlapping runs can both delete the window before either
--                inserts it, leaving duplicates that the staging duplicate
--                check in tests/quality_checks.sql will report.
-- Limitation:    rows written to /processed with a loaded_at at or below the
--                current watermark (late arrivals, backfills) are not picked up;
--                lower watermark_value in dbo.etl_watermark to reload them.
-- ============================================

IF OBJECT_ID('dbo.etl_watermark') IS NULL
BEGIN
    CREATE TABLE dbo.etl_watermark (
        table_name       VARCHAR(128) NOT NULL,
        watermark_value  DATETIME2    NOT NULL,
        updated_at       DATETIME2    NOT NULL
    );
END;

-- First run: start from whatever the initial full load already copied.
IF NOT EXISTS (SELECT 1 FROM dbo.etl_watermark WHERE table_name = 'dbo.stg_sales')
BEGIN
    INSERT INTO dbo.etl_watermark (table_name, watermark_value, updated_at)
    SELECT 'dbo.stg_sales',
           COALESCE(MAX(loaded_at), CAST('1900-01-01' AS DATETIME2)),
           GETDATE()
    FROM dbo.stg_sales;
END;

DECLARE @old_watermark DATETIME2;
DECLARE @new_watermark DATETIME2;

SET @old_watermark = (SELECT watermark_value
                      FROM dbo.etl_watermark
                      WHERE table_name = 'dbo.stg_sales');

SET @new_watermark = (SELECT MAX(loaded_at)
                      FROM ext.sales_transactions
                      WHERE loaded_at > @old_watermark);

IF @new_watermark IS NULL
BEGIN
    PRINT 'dbo.stg_sales is up to date (watermark ' + CONVERT(VARCHAR(27), @old_watermark, 121) + ').';
END
ELSE
BEGIN
    -- Remove leftovers of a previously failed run for the same window.
    DELETE FROM dbo.stg_sales
    WHERE loaded_at >  @old_watermark
      AND loaded_at <= @new_watermark;

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
    FROM ext.sales_transactions
    WHERE loaded_at >  @old_watermark
      AND loaded_at <= @new_watermark;

    UPDATE dbo.etl_watermark
    SET watermark_value = @new_watermark,
        updated_at      = GETDATE()
    WHERE table_name = 'dbo.stg_sales';

    PRINT 'Loaded dbo.stg_sales window (' + CONVERT(VARCHAR(27), @old_watermark, 121)
        + ', ' + CONVERT(VARCHAR(27), @new_watermark, 121) + '].';
END;
