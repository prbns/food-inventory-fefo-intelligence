-- ============================================================================
-- SCRIPT 01: DATABASE SCHEMA DEFINITION (3NF / DIMENSIONAL MODEL)
-- Project: Food Inventory FEFO Risk & Expiration Intelligence
-- Database: PostgreSQL 14+
-- ============================================================================

DROP TABLE IF EXISTS fct_stock_lots CASCADE;
DROP TABLE IF EXISTS dim_products CASCADE;
DROP TABLE IF EXISTS dim_locations CASCADE;
DROP TABLE IF EXISTS staging_raw_inventory CASCADE;

-- ----------------------------------------------------------------------------
-- 1. STAGING TABLE (Ingestion layer from cleaned CSV)
-- ----------------------------------------------------------------------------
CREATE TABLE staging_raw_inventory (
    lot_id VARCHAR(50),
    sku_code VARCHAR(50),
    product_name VARCHAR(150),
    category VARCHAR(100),
    storage_location VARCHAR(100),
    reception_date DATE,
    expiration_date DATE,
    stock_quantity NUMERIC(12, 2),
    unit_cost NUMERIC(10, 2),
    quality_status VARCHAR(50)
);

-- ----------------------------------------------------------------------------
-- 2. MASTER DIMENSIONS
-- ----------------------------------------------------------------------------

-- Dimension: Products & Raw Materials Catalog
CREATE TABLE dim_products (
    sku_code VARCHAR(20) PRIMARY KEY,
    product_name VARCHAR(150) NOT NULL,
    category VARCHAR(50) NOT NULL,
    unit_cost NUMERIC(10, 2) NOT NULL CHECK (unit_cost >= 0)
);

-- Dimension: Warehouse Locations & Storage Conditions
CREATE TABLE dim_locations (
    location_id SERIAL PRIMARY KEY,
    location_name VARCHAR(50) UNIQUE NOT NULL,
    temperature_zone VARCHAR(50) NOT NULL
);

-- ----------------------------------------------------------------------------
-- 3. FACT TABLE: CURRENT LOT-LEVEL INVENTORY
-- ----------------------------------------------------------------------------
CREATE TABLE fct_stock_lots (
    lot_id VARCHAR(30) PRIMARY KEY,
    sku_code VARCHAR(20) NOT NULL REFERENCES dim_products(sku_code),
    location_id INT NOT NULL REFERENCES dim_locations(location_id),
    reception_date DATE NOT NULL,
    expiration_date DATE NOT NULL,
    stock_quantity NUMERIC(12, 2) NOT NULL CHECK (stock_quantity >= 0),
    quality_status VARCHAR(20) NOT NULL CHECK (quality_status IN ('Approved', 'Quarantine', 'Blocked')),
    CONSTRAINT chk_dates_logical CHECK (expiration_date >= reception_date)
);

-- Indexes for performance on FEFO rotation queries
CREATE INDEX idx_fct_stock_sku ON fct_stock_lots(sku_code);
CREATE INDEX idx_fct_stock_exp_date ON fct_stock_lots(expiration_date ASC);
CREATE INDEX idx_fct_stock_status ON fct_stock_lots(quality_status);
