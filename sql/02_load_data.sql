-- ============================================================================
-- SCRIPT 02: DATA INGESTION & NORMALIZATION PIPELINE
-- Project: Food Inventory FEFO Risk & Expiration Intelligence
-- ============================================================================

-- Step 1: Clear previous staging data
TRUNCATE TABLE staging_raw_inventory;

-- Step 2: Load clean CSV into Staging table
-- Note: Update the path to your local repository path or use psql \copy:
-- \copy staging_raw_inventory FROM 'data/01_cleaned/01_inventory_cleaned.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- Step 3: Populate Dimension 'dim_locations' with storage condition metadata
INSERT INTO dim_locations (location_name, temperature_zone)
VALUES 
    ('Cold Room 1', 'Chilled (0°C to 4°C)'),
    ('Cold Room 2', 'Chilled (0°C to 4°C)'),
    ('Freezer -18C', 'Frozen (-18°C)'),
    ('Dry Silo A', 'Ambient Bulk Dry'),
    ('Dry Warehouse', 'Ambient Dry (15°C to 25°C)'),
    ('Heated Tank', 'Controlled Warm (45°C)'),
    ('Safety Cabinet', 'Secure Ambient'),
    ('Packaging Warehouse', 'Dry Packaging')
ON CONFLICT (location_name) DO NOTHING;

-- Step 4: Populate Dimension 'dim_products' from unique entries in staging
INSERT INTO dim_products (sku_code, product_name, category, unit_cost)
SELECT DISTINCT 
    sku_code,
    product_name,
    category,
    unit_cost
FROM staging_raw_inventory
ON CONFLICT (sku_code) DO UPDATE 
SET 
    product_name = EXCLUDED.product_name,
    category = EXCLUDED.category,
    unit_cost = EXCLUDED.unit_cost;

-- Step 5: Populate Fact Table 'fct_stock_lots' connecting foreign keys
TRUNCATE TABLE fct_stock_lots;

INSERT INTO fct_stock_lots (
    lot_id,
    sku_code,
    location_id,
    reception_date,
    expiration_date,
    stock_quantity,
    quality_status
)
SELECT 
    s.lot_id,
    s.sku_code,
    l.location_id,
    s.reception_date,
    s.expiration_date,
    s.stock_quantity,
    s.quality_status
FROM staging_raw_inventory s
JOIN dim_locations l ON s.storage_location = l.location_name;

-- Step 6: Data Verification Audit
SELECT 
    'dim_products' AS entity, COUNT(*) AS total_records FROM dim_products
UNION ALL
SELECT 
    'dim_locations' AS entity, COUNT(*) FROM dim_locations
UNION ALL
SELECT 
    'fct_stock_lots' AS entity, COUNT(*) FROM fct_stock_lots;
