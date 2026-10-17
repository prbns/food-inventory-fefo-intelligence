# Data Dictionary - Food Inventory FEFO Intelligence

This document details the relational schema, staging models, calculated metrics, and analytical attributes implemented in the **Food Inventory FEFO Risk & Expiration Intelligence System**.

---

## 1. Physical Relational Tables

### 1.1 `staging_raw_inventory`
Temporary landing table used during ETL to ingest data directly from cleaned CSV files prior to normalization.

| Column | Data Type | Nullable | Description |
| :--- | :--- | :---: | :--- |
| `lot_id` | `VARCHAR(50)` | YES | Batch or lot identifier assigned during reception |
| `sku_code` | `VARCHAR(50)` | YES | Stock Keeping Unit code |
| `product_name` | `VARCHAR(150)`| YES | Commercial product or material description |
| `category` | `VARCHAR(100)`| YES | Material category (e.g., Dairy, Egg Products) |
| `storage_location`| `VARCHAR(100)`| YES | Warehouse location name |
| `reception_date` | `DATE` | YES | Date when goods physically entered the warehouse |
| `expiration_date`| `DATE` | YES | Expiry/Best-Before date assigned by the manufacturer |
| `stock_quantity` | `NUMERIC(12,2)`| YES | Current physical inventory units |
| `unit_cost` | `NUMERIC(10,2)`| YES | Standard cost per unit in Euros (€) |
| `quality_status` | `VARCHAR(50)` | YES | Quality status assigned upon receipt |

---

### 1.2 `dim_products`
Dimension catalog table maintaining master item data and unit costs.

| Column | Data Type | Key | Constraints | Description |
| :--- | :--- | :---: | :--- | :--- |
| `sku_code` | `VARCHAR(20)` | **PK** | Unique, Not Null | Unique identifier for product or raw material |
| `product_name`| `VARCHAR(150)`| | Not Null | Standardized product title |
| `category` | `VARCHAR(50)` | | Not Null | Family classification for filtering and aggregation |
| `unit_cost` | `NUMERIC(10,2)`| | $\ge 0$ | Standard inventory cost per base unit (€) |

---

### 1.3 `dim_locations`
Dimension table storing warehouse locations and cold-chain temperature zones.

| Column | Data Type | Key | Constraints | Description |
| :--- | :--- | :---: | :--- | :--- |
| `location_id` | `SERIAL` | **PK** | Unique, Auto-inc | Synthetic surrogate key for physical location |
| `location_name`| `VARCHAR(50)` | | Unique, Not Null | Functional facility name (e.g., `Cold Room 1`) |
| `temperature_zone`| `VARCHAR(50)`| | Not Null | Operating temperature range specification |

---

### 1.4 `fct_stock_lots`
Core transactional fact table tracking inventory batches currently on hand.

| Column | Data Type | Key | Constraints | Description |
| :--- | :--- | :---: | :--- | :--- |
| `lot_id` | `VARCHAR(30)` | **PK** | Unique, Not Null | Manufacturer or internal tracking lot number |
| `sku_code` | `VARCHAR(20)` | **FK** | References `dim_products` | Associated SKU |
| `location_id` | `INT` | **FK** | References `dim_locations`| Storage bin or warehouse area |
| `reception_date`| `DATE` | | Not Null | Delivery reception date |
| `expiration_date`| `DATE` | | Not Null, $\ge \text{reception}$| Expiration date |
| `stock_quantity`| `NUMERIC(12,2)`| | $\ge 0$ | On-hand quantity |
| `quality_status`| `VARCHAR(20)` | | `Approved`, `Quarantine`, `Blocked` | Administrative QA disposition |

---

## 2. Analytical View: `vw_fefo_inventory_analysis`

Calculated view containing dynamic business intelligence metrics consumed directly by Power BI.

| Attribute | Source / Formula | Business Interpretation |
| :--- | :--- | :--- |
| `total_shelf_life_days` | `expiration_date - reception_date` | Total lifespan allocated to the lot from reception |
| `days_to_expiration` | `expiration_date - CURRENT_DATE` | Remaining days before expiry ($\Delta t$). Negative indicates expired stock |
| `total_stock_value` | `stock_quantity * unit_cost` | Total monetary valuation of the lot in Euros (€) |
| `rsl_pct_remaining` | `(days_to_expiration / total_shelf_life) * 100` | Percentage of Remaining Shelf Life (% RSL) |
| `risk_tier` | Multi-conditional `CASE` statement | Risk tier code (`00` through `05`) for sorting and filtering |
| `recommended_action` | Multi-conditional `CASE` statement | Recommended operational instruction for warehouse operators |
| `fefo_priority_rank` | `ROW_NUMBER() OVER(PARTITION BY sku_code ORDER BY expiration_date ASC, reception_date ASC)` | Discrete FEFO picking order: `1` must be dispatched first for that SKU |

---

## 3. Risk Classification Reference

| Risk Tier | Expiry Threshold ($\Delta t$) | Quality Status | Operational Intent |
| :--- | :---: | :---: | :--- |
| **00. Blocked / Quarantine** | Any | `Blocked` or `Quarantine` | Physical quarantine. Do not dispatch. |
| **01. Expired** | $\Delta t < 0$ | Any | Immediate write-off and destruction order. |
| **02. Critical (< 15 days)** | $0 \le \Delta t \le 15$ | `Approved` | High-priority production routing or immediate dispatch. |
| **03. High Risk (16-45 days)** | $16 \le \Delta t \le 45$ | `Approved` | Plan into upcoming production run. |
| **04. Medium Risk (46-90 days)**| $46 \le \Delta t \le 90$ | `Approved` | Standard rotation plan. |
| **05. Optimal (> 90 days)** | $\Delta t > 90$ | `Approved` | Stable stock. Standard storage parameters. |