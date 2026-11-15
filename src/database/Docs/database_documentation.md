# Database Module Documentation
## Smart Energy Analytics & Prediction Project

### Overview
This document provides comprehensive documentation for the database layer of the Smart Energy Analytics project. It covers the relational schema, data dictionary, data transformation and loading pipeline, validation results, and analytical views built on Microsoft SQL Server.

---

### Table of Contents
1. [Schema Design](#1-schema-design)
2. [Data Dictionary](#2-data-dictionary)
3. [Data Transformation](#3-data-transformation)
4. [Data Loading](#4-data-loading)
5. [Data Validation Results](#5-data-validation-results)
6. [Analytical Views & Serving Layer](#6-analytical-views--serving-layer)
7. [Key Business Insights](#7-key-business-insights)
8. [File Structure](#8-file-structure)

---

## 1. Schema Design

**Database:** `ElectricityDB`  
**Engine:** Microsoft SQL Server 2019 (T-SQL)  
**Architecture:** Relational — Parent/Child (One-to-Many)

The database consists of two relational tables with a One-to-Many (1:N) relationship:
- **Households:** Parent table with `household_id` as the Primary Key.
- **ElectricityReadings:** Child table with a Composite Primary Key `(household_id, reading_time)` and a Foreign Key referencing the `Households` table.

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
| **Composite Primary Key** `(household_id, reading_time)` in `ElectricityReadings` | Physically prevents duplicate readings for the same house at the same timestamp |
| **Foreign Key** on `household_id` | Enforces referential integrity — no reading can exist without a valid household |
| **Non-Clustered Indexes** on `household_id` and `reading_time` | Accelerates time-range queries for dashboard and ML workloads |
| **FLOAT data type** for sensor columns | Accommodates decimal precision required for voltage, amperage, and power readings |

---

## 2. Data Dictionary

### Table: `dbo.Households`
> Parent table storing metadata for each monitored residence. Contains 3 records (one per household).

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
| `issues` | `FLOAT` | NULL | Dataset-provided field — exact semantics to be confirmed from source documentation |
| `internal_temperature` | `FLOAT` | NULL | Indoor ambient temperature (°C) |
| `internal_humidity` | `FLOAT` | NULL | Indoor relative humidity (%) |
| `external_temperature` | `FLOAT` | NULL | Outdoor ambient temperature (°C) — unified from two source column variants (see Section 3) |
| `external_humidity` | `FLOAT` | NULL | Outdoor relative humidity (%) |

---

## 3. Data Transformation

Before loading into SQL Server, the following transformations were applied to the raw CSV files:

### 3.1 Adding Household Identifier
Each CSV file represents one household. A `household_id` column was added programmatically to tag every row with its source household before concatenation:

```python
df['household_id'] = 'House_01'   # repeated per file
```

### 3.2 Column Name Unification (Schema Drift Resolution)
`House_01_cleaned.csv` contained a misspelled column `external_temparature` (with **'a'** instead of **'e'**) alongside the correctly named `external_temperature`. Both columns carried partial data.

Rather than discarding either column, `combine_first()` was used to merge them into a single unified column:

```python
df_house_01['external_temperature'] = (
    df_house_01['external_temperature']
    .combine_first(df_house_01['external_temparature'])
)
df_house_01.drop(columns=['external_temparature'], inplace=True)
```

This preserves all 42,432 outdoor temperature readings for House_01, which are critical for AC-temperature correlation analysis. The final column stored in the database is always `external_temperature`.

### 3.3 Column Selection & Alignment
After concatenation, only the expected schema columns are retained to ensure consistency across all three households:

```python
expected_columns = [
    'household_id', 'reading_time', 'V', 'A', 'P_agg',
    'ac_1', 'ac_2', 'boiler', 'fridge', 'washing_machine',
    'issues', 'internal_temperature', 'internal_humidity',
    'external_temperature', 'external_humidity'
]
df_combined = df_combined[[col for col in expected_columns if col in df_combined.columns]]
```

---

## 4. Data Loading

### Source Files

| File | Household | Records |
|---|---|---|
| `House_01_cleaned.csv` | House_01 | 42,432 |
| `House_03_cleaned.csv` | House_03 | 42,861 |
| `House_04_cleaned.csv` | House_04 | 34,082 |
| **Total** | | **119,375** |

### Loading Configuration

| Parameter | Value |
|---|---|
| **Script** | `load_data.py` |
| **Libraries** | Python Pandas + SQLAlchemy |
| **Connection** | `mssql+pyodbc` via ODBC Driver 17 for SQL Server |
| **Target Database** | `ElectricityDB` on `localhost` |
| **Target Table** | `dbo.ElectricityReadings` |
| **Insert Mode** | `append` (non-destructive) |
| **Chunk Size** | 5,000 rows per batch |
| **Missing Values** | Preserved as `NULL` where applicable |

### Loading Pipeline

```
[House_01_cleaned.csv]  ─┐
[House_03_cleaned.csv]  ─┼──► pd.read_csv()  ──► Add household_id
[House_04_cleaned.csv]  ─┘
            │
            ▼
    Column unification (external_temparature fix)
            │
            ▼
    pd.concat() → 119,375 unified rows
            │
            ▼
    SQLAlchemy → SQL Server (ElectricityDB)
            │
            ▼
    to_sql(chunksize=5000) → dbo.ElectricityReadings
```

---

## 5. Data Validation Results

All validation checks were executed via `02_data_quality_checks.sql` after the loading pipeline completed:

| Validation Check | Expected | Actual | Status |
|---|---|---|---|
| Total record count | 119,375 | 119,375 | ✅ PASSED |
| House_01 record count | 42,432 | 42,432 | ✅ PASSED |
| House_03 record count | 42,861 | 42,861 | ✅ PASSED |
| House_04 record count | 34,082 | 34,082 | ✅ PASSED |
| Duplicate `(household_id, reading_time)` pairs | 0 | 0 | ✅ PASSED |
| Negative `P_agg` power values | 0 | 0 | ✅ PASSED |
| NULL `reading_time` values | 0 | 0 | ✅ PASSED |

All 7 checks passed. The data integrity constraints defined in the schema (Composite PK, FK) are consistent with the validation results.

---

## 6. Analytical Views & Serving Layer

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

## 7. Key Business Insights

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

### Temperature Impact on Energy Consumption
| Temperature Bracket | Avg Total Power (W) | Avg AC Power (W) |
|---|---|---|
| < 15°C | ~850W | ~120W |
| 15°C – 25°C | ~1,100W | ~350W |
| 25°C – 30°C | ~1,450W | ~680W |
| > 30°C | ~2,600W | ~1,900W |

> At temperatures above 30°C, AC consumption surges to **3× its baseline**, dominating total household energy use.

---

## 8. File Structure

```
src/database/
├── 01_create_database.sql        # Database, tables, Composite PK, FK, indexes
├── 02_data_quality_checks.sql    # Validation framework (7 checks)
├── 03_analytical_views.sql       # Serving layer views for Dashboard & ML teams
├── 04_business_insights.sql      # Business analytics queries
├── load_data.py                  # Python ETL pipeline (Pandas + SQLAlchemy)
├── README.md                     # Quick reference schema overview
└── Docs/
    └── database_documentation.md  # This file — full technical documentation
```
