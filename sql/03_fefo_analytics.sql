-- ============================================================================
-- SCRIPT 03: FEFO ANALYTICS, EXPIRATION RISK TIERS & INVENTORY INTELLIGENCE
-- Project: Food Inventory FEFO Risk & Expiration Intelligence
-- Database: PostgreSQL 14+
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. DETAILED VIEW: LOT RISK ANALYSIS & FEFO ROTATION PRIORITY
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_fefo_inventory_analysis AS
WITH lot_base_metrics AS (
    SELECT 
        f.lot_id,
        f.sku_code,
        p.product_name,
        p.category,
        l.location_name,
        l.temperature_zone,
        f.reception_date,
        f.expiration_date,
        f.stock_quantity,
        p.unit_cost,
        f.quality_status,
        -- Total shelf life days allocated to the batch
        (f.expiration_date - f.reception_date) AS total_shelf_life_days,
        -- Remaining shelf life days relative to the current analysis date
        (f.expiration_date - CURRENT_DATE) AS days_to_expiration,
        -- Financial stock valuation (€)
        ROUND((f.stock_quantity * p.unit_cost), 2) AS total_stock_value
    FROM fct_stock_lots f
    JOIN dim_products p ON f.sku_code = p.sku_code
    JOIN dim_locations l ON f.location_id = l.location_id
)
SELECT 
    lot_id,
    sku_code,
    product_name,
    category,
    location_name,
    temperature_zone,
    reception_date,
    expiration_date,
    stock_quantity,
    unit_cost,
    quality_status,
    total_shelf_life_days,
    days_to_expiration,
    total_stock_value,
    -- Percentage of Remaining Shelf Life (% RSL)
    CASE 
        WHEN total_shelf_life_days > 0 
        THEN ROUND(((days_to_expiration::NUMERIC / total_shelf_life_days::NUMERIC) * 100), 1)
        ELSE 0.0 
    END AS rsl_pct_remaining,
    -- Expiration Risk Bands
    CASE 
        WHEN quality_status = 'Blocked' THEN '00. Blocked / Quarantine'
        WHEN days_to_expiration < 0 THEN '01. Expired'
        WHEN days_to_expiration <= 15 THEN '02. Critical (< 15 days)'
        WHEN days_to_expiration <= 45 THEN '03. High Risk (16-45 days)'
        WHEN days_to_expiration <= 90 THEN '04. Medium Risk (46-90 days)'
        ELSE '05. Optimal (> 90 days)'
    END AS risk_tier,
    -- Actionable Operational Recommendations
    CASE 
        WHEN quality_status = 'Blocked' THEN 'Move to Quarantine / Await QA Disposition'
        WHEN days_to_expiration < 0 THEN 'Immediate Write-Off / Destroy Lot'
        WHEN days_to_expiration <= 15 THEN 'Priority 1: Immediate Consumption or Flash Sale'
        WHEN days_to_expiration <= 45 THEN 'Priority 2: Fast-Track to Production Schedule'
        WHEN days_to_expiration <= 90 THEN 'Standard Rotation Plan'
        ELSE 'Regular Storage'
    END AS recommended_action,
    -- Strict FEFO Rotation Priority: 1 = Must be consumed / dispatched first per SKU
    ROW_NUMBER() OVER (
        PARTITION BY sku_code 
        ORDER BY expiration_date ASC, reception_date ASC
    ) AS fefo_priority_rank
FROM lot_base_metrics;

-- ----------------------------------------------------------------------------
-- 2. EXECUTIVE RISK SUMMARY VIEW: FINANCIAL INVENTORY AT RISK
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_fefo_risk_summary AS
SELECT 
    risk_tier,
    recommended_action,
    COUNT(lot_id) AS total_lots,
    SUM(stock_quantity) AS total_stock_quantity,
    SUM(total_stock_value) AS total_val_in_risk_eur,
    ROUND(AVG(days_to_expiration), 1) AS avg_days_remaining,
    ROUND(
        (SUM(total_stock_value) / SUM(SUM(total_stock_value)) OVER ()) * 100, 
        2
    ) AS pct_total_inventory_value
FROM vw_fefo_inventory_analysis
GROUP BY risk_tier, recommended_action
ORDER BY risk_tier ASC;

-- ----------------------------------------------------------------------------
-- 3. FEFO PICKING PRIORITY AUDIT
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_fefo_pick_priority_audit AS
SELECT 
    sku_code,
    product_name,
    lot_id,
    fefo_priority_rank,
    expiration_date,
    stock_quantity,
    total_stock_value,
    risk_tier,
    location_name
FROM vw_fefo_inventory_analysis
WHERE quality_status = 'Approved'
ORDER BY sku_code ASC, fefo_priority_rank ASC;
