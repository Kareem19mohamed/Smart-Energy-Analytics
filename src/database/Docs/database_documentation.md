# Database Module Documentation
## Smart Energy Analytics & Prediction Project

### Overview
This document provides the complete technical documentation for the database layer (`ElectricityDB`) of the Smart Energy Analytics project. It covers the relational schema, data dictionary, constraints and indexes, data transformation and loading pipeline, pre-load and post-load validation framework, analytical serving views, and business insights built on Microsoft SQL Server.

---

### Table of Contents
1. [Schema Overview & Design](#1-schema-overview--design)
2. [Table Definitions & Data Dictionary](#2-table-definitions--data-dictionary)
3. [Constraints & Indexes](#3-constraints--indexes)
4. [Data Transformation & Loading Pipeline](#4-data-transformation--loading-pipeline)
5. [Data Quality & Validation Framework](#5-data-quality--validation-framework)
6. [Analytical Views & Serving Layer](#6-analytical-views--serving-layer)
7. [Key Business Insights](#7-key-business-insights)
8. [Module Structure](#8-module-structure)

---

## 1. Schema Overview & Design

**Database:** `ElectricityDB`  
**Engine:** Microsoft SQL Server (T-SQL)  
**Architecture:** Relational — Parent/Child (One-to-Many)

The database consists of two relational tables with a One-to-Many (`1:N`) relationship:
- **Households (`dbo.Households`):** Parent table with a standard Primary Key: `household_id`.
- **ElectricityReadings (`dbo.ElectricityReadings`):** Child table with a Composite Primary Key: `(household_id, reading_time)` and a Foreign Key referencing `dbo.Households(household_id)`.

```
┌──────────────────────────────────────┐
│            dbo.Households            │
│  ──────────────────────────────────  │
│  household_id   [PK]  VARCHAR(20)    │
│  source_file          VARCHAR(100)   │
│  description          NVARCHAR(255)  │
│  created_at           DATETIME2      │
└──────────────────┬───────────────────┘
                   │  1
                   │
                   │  One-to-Many (1:N)
                   │
                   │  ∞
┌──────────────────▼───────────────────┐
│        dbo.ElectricityReadings       │
│  ──────────────────────────────────  │
│  household_id   [PK, FK] VARCHAR(20) │
│  reading_time   [PK]     DATETIME2(0)│
│  V, A, P_agg             FLOAT       │
│  ac_1, ac_2, boiler      FLOAT       │
│  fridge, washing_machine FLOAT       │
│  issues                  FLOAT       │
│  internal_temp/humidity  FLOAT       │
│  external_temp/humidity  FLOAT       │
└──────────────────────────────────────┘
```

---

## 2. Table Definitions & Data Dictionary

### A. Parent Table: `dbo.Households`
> Stores metadata for each monitored residence (3 records total).

| Column Name | Data Type | Constraint | Description |
|---|---|---|---|
| `household_id` | `VARCHAR(20)` | **PRIMARY KEY** | Unique residence identifier (`House_01`, `House_03`, `House_04`) |
| `source_file` | `VARCHAR(100)` | `NOT NULL` | Source CSV file name (`House_01_cleaned.csv`, etc.) |
| `description` | `NVARCHAR(255)` | `NULL` | Household description |
| `created_at` | `DATETIME2` | `DEFAULT SYSDATETIME()` | Record creation timestamp |

---

### B. Child Table: `dbo.ElectricityReadings`
> Stores 15-minute interval smart meter readings (**119,375 records** across three households spanning July 2022 – September 2023).

| Column Name | Data Type | Constraint | Description |
|---|---|---|---|
| `household_id` | `VARCHAR(20)` | **PK**, **FK** → `Households` | Foreign key referencing `dbo.Households(household_id)` |
| `reading_time` | `DATETIME2(0)` | **PK**, `NOT NULL` | Timestamp of the 15-minute reading (Composite PK with `household_id`) |
| `V` | `FLOAT` | `NULL` | Grid voltage in Volts (~230V standard) |
| `A` | `FLOAT` | `NULL` | Current load in Amperes |
| `P_agg` | `FLOAT` | `NULL` | Total active aggregate power (Watts) |
| `ac_1` | `FLOAT` | `NULL` | Air Conditioner Unit 1 power (Watts) |
| `ac_2` | `FLOAT` | `NULL` | Air Conditioner Unit 2 power (Watts) |
| `boiler` | `FLOAT` | `NULL` | Water boiler / heater power (Watts) |
| `fridge` | `FLOAT` | `NULL` | Refrigerator power (Watts) |
| `washing_machine` | `FLOAT` | `NULL` | Washing machine power (Watts) |
| `issues` | `FLOAT` | `NULL` | Dataset-provided indicator field (retained from raw source CSV) |
| `internal_temperature` | `FLOAT` | `NULL` | Indoor ambient temperature (°C) |
| `internal_humidity` | `FLOAT` | `NULL` | Indoor relative humidity (%) |
| `external_temperature` | `FLOAT` | `NULL` | Outdoor ambient temperature (°C) — unified from source columns |
| `external_humidity` | `FLOAT` | `NULL` | Outdoor relative humidity (%) |

---

## 3. Constraints & Indexes

| Object | Type | Definition & Justification |
|---|---|---|
| `PK_Households` | **Clustered Primary Key** | On `dbo.Households(household_id)` — uniquely identifies each household. |
| `PK_ElectricityReadings` | **Composite Primary Key (Clustered)** | On `dbo.ElectricityReadings(household_id, reading_time)` — physically prevents duplicate readings per house and serves as the Clustered Index for household-ordered time-series scans. |
| `FK_Readings_Households` | **Foreign Key** | Enforces referential integrity between `ElectricityReadings.household_id` and `Households.household_id`. |
| `IX_Readings_Time` | **Non-Clustered Index** | Explicitly created via `CREATE NONCLUSTERED INDEX` on `dbo.ElectricityReadings(reading_time)` to accelerate cross-household time-range queries. (A redundant index on `(household_id, reading_time)` was intentionally omitted since `PK_ElectricityReadings` already indexes that exact key order). |
| **Idempotent Creation** | **Safety Check** | `01_create_database.sql` checks `IF OBJECT_ID(...) IS NULL` before creating tables so re-running the script does not accidentally drop existing tables or data. |

---

## 4. Data Transformation & Loading Pipeline

### 4.1 Source Files & Record Counts

| Source File | `household_id` | Records |
|---|---|---|
| `House_01_cleaned.csv` | `House_01` | 42,432 |
| `House_03_cleaned.csv` | `House_03` | 42,861 |
| `House_04_cleaned.csv` | `House_04` | 34,082 |
| **Total Unified Dataset** | **3 Households** | **119,375** |

### 4.2 Data Transformations (`load_data.py`)
1. **Path Resolution (`resolve_data_dir`):** Automatically locates the CSV files in `<project_root>/data`, `<project_root>/data/processed`, or the script directory.
2. **Adding `household_id`:** Tags each DataFrame with its corresponding `household_id` (`House_01`, `House_03`, `House_04`) prior to concatenation.
3. **Column Name Unification (Schema Drift Fix):** `House_01_cleaned.csv` contained a misspelled column `external_temparature` alongside `external_temperature`. `prepare_and_validate_house()` merges both columns using `combine_first()` into `external_temperature` and drops the misspelled column.
4. **Timestamp Standardization:** Renames `timestamp` to `reading_time` and converts values to `DATETIME2(0)` via `pd.to_datetime()`.
5. **Per-File Schema & Count Validation:** Validates each individual house DataFrame for all 15 required columns and exact expected row count before `pd.concat()`.

### 4.3 Database Loading Configuration
- **Libraries:** Python `pandas` + `SQLAlchemy` (`pyodbc` with `ODBC Driver 17 for SQL Server`, `fast_executemany=True`)
- **Server Configuration:** Reads `SQL_SERVER` environment variable (defaults to `localhost`) and verifies connectivity via `SELECT 1`
- **Atomic Transaction:** Executes `DELETE FROM dbo.ElectricityReadings`, `DELETE FROM dbo.Households`, and loads both `dbo.Households` and `dbo.ElectricityReadings` (`chunksize=5000`) inside a single `with engine.begin() as conn:` transaction so any failure triggers a full rollback
- **Missing Values:** Preserved as `NULL` where applicable

---

## 5. Data Quality & Validation Framework

Validation is split into two distinct stages to separate **source CSV quality** from **database storage integrity**:

### Stage A: Pre-Load Validation in Python (`load_data.py`)
Executed on the CSV DataFrames **before** inserting into SQL Server:
1. **Per-House Column Check:** Ensures all 15 required columns exist in each CSV file before concatenation.
2. **Per-House & Total Row Count Check:** Verifies `House_01 = 42,432`, `House_03 = 42,861`, `House_04 = 34,082`, and `Total = 119,375`.
3. **Pre-Load NULL Timestamp Check:** Confirms `0` NULL values in `reading_time` before hitting the `NOT NULL` SQL constraint.
4. **Pre-Load Duplicate Key Check:** Confirms `0` duplicate `(household_id, reading_time)` rows in the source CSVs before hitting the Composite Primary Key constraint.

### Stage B: Post-Load Verification in SQL Server (`02_data_quality_checks.sql` & `load_data.py`)
Executed inside SQL Server **after** loading:

| Validation Check | Expected | Actual | Status |
|---|---|---|---|
| Total record count in `dbo.ElectricityReadings` | 119,375 | 119,375 | ✅ PASSED |
| `House_01` count (`LEFT JOIN` from `dbo.Households`) | 42,432 | 42,432 | ✅ PASSED |
| `House_03` count (`LEFT JOIN` from `dbo.Households`) | 42,861 | 42,861 | ✅ PASSED |
| `House_04` count (`LEFT JOIN` from `dbo.Households`) | 34,082 | 34,082 | ✅ PASSED |
| Duplicate `(household_id, reading_time)` pairs | 0 | 0 | ✅ PASSED |
| NULL `reading_time` values | 0 | 0 | ✅ PASSED |
| Negative power readings (`Rows_With_Negative_Readings`) | 0 | 0 | ✅ PASSED |
| 15-minute interval continuity (`DATEDIFF(MINUTE, LAG(reading_time), reading_time) = 15`) | 99.99% regular (119,360 / 119,372 transitions) | `House_01`: 1 gap, `House_03`: 0 gaps, `House_04`: 11 gaps | ✅ VERIFIED |

---

## 6. Analytical Views & Serving Layer

Created in `03_analytical_views.sql` for downstream teams:

### 6.1 `dbo.vw_Household_KPIs` (For BI Dashboard Team)
Provides per-household KPIs (`Total_Readings`, `Regular_15m_Readings`, `Data_Start_Date`, `Data_End_Date`, `Total_Monitored_Days`, `Avg_Power_Watts`, `Max_Peak_Power_Watts`, `Total_Energy_kWh` verified on regular 15-minute intervals, and average indoor/outdoor temperatures).

### 6.2 `dbo.vw_ML_Feature_Store` (For Machine Learning Team)
Uses two CTEs (`StepIntervals` and `WindowChecked`) to verify step-by-step 15-minute regularity across each window (`SUM(Is_Irregular_Step) OVER (ROWS BETWEEN ... PRECEDING AND CURRENT ROW) = 0`) before emitting time-series lag features:

| Feature | Logic | Description |
|---|---|---|
| `Lag_15m_Power` | `LAG(P_agg, 1)` when `Prev_Step_Min = 15` | Power reading exactly 15 minutes ago (`NULL` if preceded by a time gap) |
| `Lag_1h_Power` | `LAG(P_agg, 4)` when `Irregular_Steps_Last_4 = 0` | Power reading 1 hour ago across 4 verified consecutive 15-minute steps |
| `Lag_24h_Power` | `LAG(P_agg, 96)` when `Irregular_Steps_Last_96 = 0` | Power reading 24 hours ago across 96 verified consecutive 15-minute steps |
| `Rolling_1h_Avg_Power` | `AVG(P_agg)` over 4 rows when `Irregular_Steps_Last_3 = 0` | Rolling 1-hour average power across 4 contiguous 15-minute readings |
| `Target_Next_15m_Power` | `LEAD(P_agg, 1)` when `Next_Step_Min = 15` | Next 15-minute power target variable |
| `Is_Weekend` | `((DATEPART(WEEKDAY, reading_time) + @@DATEFIRST) % 7) IN (0, 1)` | Server `@@DATEFIRST`-independent and language-independent weekend flag |
| `Total_AC_Power` | `CASE WHEN ac_1 IS NULL AND ac_2 IS NULL THEN NULL ELSE ISNULL(ac_1,0)+ISNULL(ac_2,0) END` | Combined AC power preserving true `NULL` when both units are missing |

---

## 7. Key Business Insights

Implemented in `04_business_insights.sql`:
1. **Household Consumption Ranking:** Compares both `Total_Energy_Rank` (`SUM(P_agg * 0.25 / 1000.0)`) and `Avg_Power_Rank` (`AVG(P_agg)`) alongside `Total_Monitored_Days` (`House_01` ranks #1 in cumulative kWh over 443 days, while `House_04` ranks #1 in average power draw over 355 days).
2. **Peak Consumption Hours:** Identifies top 3 peak hours per household and compares all 4 sub-metered appliances (`AC`, `Boiler`, `Fridge`, `Washing Machine`) to classify the `Primary_Peak_Driver`.
3. **Appliance Energy Contribution:** Computes kWh and percentage share for each monitored appliance plus `Other_Unmetered_Share_Pct` (representing the remaining difference between `P_agg` and the 5 sub-metered appliances).
4. **Temperature vs. Consumption:** Groups readings into continuous temperature brackets (`< 15C`, `15C - 20C`, `20C - 25C`, `25C - 30C`, `30C - 35C`, `35C+`) ordered chronologically by `Bracket_Order`.
5. **Weekday vs. Weekend Demand:** Uses the unified `@@DATEFIRST`-independent weekend formula to compare overall and per-appliance power consumption.

---

## 8. Module Structure

```
src/database/
├── 01_create_database.sql        # Database, tables, constraints, and nonclustered index
├── 02_data_quality_checks.sql    # Post-load SQL validation & 15m interval continuity checks
├── 03_analytical_views.sql       # KPI & gap-verified ML Feature Store views
├── 04_business_insights.sql      # Business analytics queries
├── load_data.py                  # Python ETL & pre/post-load validation pipeline
└── Docs/
    └── database_documentation.md # Complete technical documentation
```
