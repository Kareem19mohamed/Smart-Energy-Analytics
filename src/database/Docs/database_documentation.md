# Database Module Documentation
## Smart Energy Analytics & Prediction Project

### Overview
This document provides comprehensive documentation for the database layer of the Smart Energy Analytics project. It covers the relational schema, data dictionary, validation framework, and analytical views built on Microsoft SQL Server.

---

### Table of Contents
1. [Schema Design](#1-schema-design)
2. [Data Dictionary](#2-data-dictionary)
3. [ETL Pipeline](#3-etl-pipeline)
4. [Data Validation Results](#4-data-validation-results)
5. [Analytical Views & Serving Layer](#5-analytical-views--serving-layer)
6. [Key Business Insights](#6-key-business-insights)
7. [File Structure](#7-file-structure)

---

## 1. Schema Design

**Database:** `ElectricityDB`  
**Engine:** Microsoft SQL Server (T-SQL)  
**Architecture:** Relational Model with Parent-Child relationship

```
┌─────────────────────────┐
│     dbo.Households      │
│  ──────────────────     │
│  household_id  [PK]     │
│  source_file            │
│  description            │
│  created_at             │
└───────────┬─────────────┘
            │  1
            │
            │ One-to-Many
            │
            │  ∞
┌───────────▼──────────────────────────┐
│        dbo.ElectricityReadings       │
│  ──────────────────────────────      │
│  household_id   [PK, FK]             │
│  reading_time   [PK]                 │
│  V, A, P_agg                         │
│  ac_1, ac_2, boiler                  │
│  fridge, washing_machine             │
│  internal_temperature/humidity       │
│  external_temperature/humidity       │
└──────────────────────────────────────┘
```

### Design Decisions
| Decision | Justification |
|---|---|
| **Composite Primary Key** `(household_id, reading_time)` | Physically prevents duplicate readings for the same house at the same timestamp |
| **Foreign Key** on `household_id` | Enforces referential integrity — no reading can exist without a valid household |
| **Non-Clustered Indexes** | Accelerates time-range queries for dashboard and ML workloads |
| **FLOAT data type** for sensor columns | Accommodates decimal precision required for voltage, amperage, and power readings |

---

## 2. Data Dictionary

### Table: `dbo.Households`
> Parent table storing metadata for each monitored residence.

| Column | Data Type | Constraint | Description |
|---|---|---|---|
| `household_id` | `VARCHAR(20)` | **PRIMARY KEY** | Unique residence identifier (`House_01`, `House_03`, `House_04`) |
| `source_file` | `VARCHAR(100)` | NOT NULL | Original CSV source file name |
| `description` | `NVARCHAR(255)` | NULL | Summary of monitored appliances |
| `created_at` | `DATETIME2` | DEFAULT `SYSDATETIME()` | Record creation timestamp |

---

### Table: `dbo.ElectricityReadings`
> Child table storing 15-minute interval smart meter readings. Contains **119,375 records** across three households spanning July 2022 – September 2023.

| Column | Data Type | Constraint | Description |
|---|---|---|---|
| `household_id` | `VARCHAR(20)` | **PK**, **FK** → Households | References parent household |
| `reading_time` | `DATETIME2(0)` | **PK** | Timestamp of the 15-minute interval reading |
| `V` | `FLOAT` | NULL | Grid voltage in Volts (~230V standard) |
| `A` | `FLOAT` | NULL | Current load in Amperes |
| `P_agg` | `FLOAT` | NULL | Total active aggregate power (Watts) |
| `ac_1` | `FLOAT` | NULL | Air Conditioner Unit 1 power (Watts) |
| `ac_2` | `FLOAT` | NULL | Air Conditioner Unit 2 power (Watts) |
| `boiler` | `FLOAT` | NULL | Water boiler / heater power (Watts) |
| `fridge` | `FLOAT` | NULL | Refrigerator power (Watts) |
| `washing_machine` | `FLOAT` | NULL | Washing machine power (Watts) |
| `issues` | `FLOAT` | NULL | Synthetic data quality issues score |
| `internal_temperature` | `FLOAT` | NULL | Indoor ambient temperature (°C) |
| `internal_humidity` | `FLOAT` | NULL | Indoor relative humidity (%) |
| `external_temperature` | `FLOAT` | NULL | Outdoor ambient temperature (°C) |
| `external_humidity` | `FLOAT` | NULL | Outdoor relative humidity (%) |

---

## 3. ETL Pipeline

The ingestion pipeline (`load_data.py`) performs the following stages:

```
[House_01_cleaned.csv]  ─┐
[House_03_cleaned.csv]  ─┼──► pd.read_csv()
[House_04_cleaned.csv]  ─┘
            │
            ▼
    Add household_id column
            │
            ▼
    Handle Schema Drift
    (House_01: external_temparature typo)
    combine_first() merges both columns
            │
            ▼
    pd.concat() → 119,375 unified rows
            │
            ▼
    SQLAlchemy → SQL Server connection
            │
            ▼
    to_sql(chunksize=5000) → ElectricityReadings
```

### Schema Drift Resolution
House_01's CSV contained a column named `external_temparature` (typo with **'a'** instead of **'e'**) alongside a correctly named `external_temperature` column. Rather than discarding either column:

```python
df_house_01['external_temperature'] = (
    df_house_01['external_temperature']
    .combine_first(df_house_01['external_temparature'])
)
df_house_01.drop(columns=['external_temparature'], inplace=True)
```

This preserves all 42,432 outdoor temperature readings for House_01, which are critical for AC-temperature correlation analysis.

---

## 4. Data Validation Results

All validation checks executed via `02_data_quality_checks.sql`:

| Validation Check | Expected | Actual | Status |
|---|---|---|---|
| Total record count | 119,375 | 119,375 | ✅ PASSED |
| House_01 record count | 42,432 | 42,432 | ✅ PASSED |
| House_03 record count | 42,861 | 42,861 | ✅ PASSED |
| House_04 record count | 34,082 | 34,082 | ✅ PASSED |
| Duplicate timestamps | 0 | 0 | ✅ PASSED |
| Negative power values | 0 | 0 | ✅ PASSED |
| NULL reading_time | 0 | 0 | ✅ PASSED |

---

## 5. Analytical Views & Serving Layer

Two SQL Views are created in `03_analytical_views.sql` to serve downstream teams:

### `dbo.vw_Household_KPIs`
> For the **BI Dashboard team** (Power BI / Tableau)

Provides per-household summary metrics:
- Total readings and monitored date range
- Average, max, and total energy consumption (kWh)
- Average indoor and outdoor temperatures

### `dbo.vw_ML_Feature_Store`
> For the **Machine Learning team**

Pre-computes time-series features using SQL Window Functions:

| Feature | SQL Function | Description |
|---|---|---|
| `Lag_15m_Power` | `LAG(P_agg, 1)` | Power reading 15 minutes ago |
| `Lag_1h_Power` | `LAG(P_agg, 4)` | Power reading 1 hour ago |
| `Lag_24h_Power` | `LAG(P_agg, 96)` | Power reading 24 hours ago |
| `Rolling_1h_Avg_Power` | `AVG() OVER (ROWS 3 PRECEDING)` | Rolling average over last hour |
| `Target_Next_15m_Power` | `LEAD(P_agg, 1)` | Target variable for prediction |
| `Is_Weekend` | `DATEPART(WEEKDAY)` | Binary weekend indicator |

---

## 6. Key Business Insights

Results from `04_business_insights.sql`:

### Household Consumption Ranking
| Rank | Household | Total Energy (kWh) | Est. Cost (EUR) |
|---|---|---|---|
| 1 | House_01 | 3,508.71 | €701.74 |
| 2 | House_04 | 3,201.44 | €640.29 |
| 3 | House_03 | 2,912.89 | €582.58 |

### Peak Consumption Hours
Peak demand occurs between **17:00 – 19:00 (5–7 PM)** driven primarily by:
- Air Conditioning units responding to afternoon heat buildup
- Water Boilers activated upon residents returning home

### Temperature Impact
| Temperature Bracket | Avg Total Power (W) | Avg AC Power (W) |
|---|---|---|
| < 15°C | ~850W | ~120W |
| 15°C – 25°C | ~1,100W | ~350W |
| 25°C – 30°C | ~1,450W | ~680W |
| > 30°C | ~2,600W | ~1,900W |

> At temperatures above 30°C, AC consumption surges to **3× its baseline**, dominating total household energy use.

---

## 7. File Structure

```
src/database/
├── 01_create_database.sql        # Database, tables, keys, indexes
├── 02_data_quality_checks.sql    # Validation framework (5 checks)
├── 03_analytical_views.sql       # Serving layer views for Dashboard & ML
├── 04_business_insights.sql      # Business analytics queries
├── load_data.py                  # Python ETL pipeline
├── README.md                     # Quick reference schema overview
└── Docs/
    └── database_documentation.md  # This file — full technical documentation
```
