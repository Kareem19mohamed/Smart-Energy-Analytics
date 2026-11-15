# Database Documentation - ElectricityDB

## 1. Schema Overview
Database: `ElectricityDB`  
Engine: Microsoft SQL Server (T-SQL)

The database consists of two relational tables with a One-to-Many (1:N) relationship:
- **Households:** Parent table with a standard Primary Key: `household_id`.
- **ElectricityReadings:** Child table with a Composite Primary Key: `(household_id, reading_time)` and a Foreign Key referencing `dbo.Households(household_id)`.

```
[dbo.Households] (Parent)
    │ PK: household_id
    │
    └─── 1 : Many
         │
         ▼
[dbo.ElectricityReadings] (Child)
    Composite PK: (household_id, reading_time)
    FK: household_id REFERENCES dbo.Households(household_id)
```

---

## 2. Table Definitions & Data Dictionary

### A. Parent Table: `dbo.Households`
| Column Name | Data Type | Constraint | Description |
|---|---|---|---|
| `household_id` | `VARCHAR(20)` | PRIMARY KEY | Unique household identifier (`House_01`, `House_03`, `House_04`) |
| `source_file` | `VARCHAR(100)` | NOT NULL | Source CSV filename |
| `description` | `NVARCHAR(255)` | NULL | Household description |
| `created_at` | `DATETIME2` | DEFAULT SYSDATETIME() | Record creation timestamp |

### B. Child Table: `dbo.ElectricityReadings`
Stores 15-minute smart meter readings (119,375 total records).

| Column Name | Data Type | Constraint | Description |
|---|---|---|---|
| `household_id` | `VARCHAR(20)` | PK, FK | Foreign key referencing `dbo.Households(household_id)` |
| `reading_time` | `DATETIME2(0)` | PK, NOT NULL | Timestamp of reading (Composite PK with `household_id`) |
| `V` | `FLOAT` | NULL | Voltage (Volts) |
| `A` | `FLOAT` | NULL | Current (Amperes) |
| `P_agg` | `FLOAT` | NULL | Active aggregate power (Watts) |
| `ac_1` | `FLOAT` | NULL | AC Unit 1 power (Watts) |
| `ac_2` | `FLOAT` | NULL | AC Unit 2 power (Watts) |
| `boiler` | `FLOAT` | NULL | Water boiler power (Watts) |
| `fridge` | `FLOAT` | NULL | Refrigerator power (Watts) |
| `washing_machine` | `FLOAT` | NULL | Washing machine power (Watts) |
| `issues` | `FLOAT` | NULL | Dataset-provided indicator field (retained from raw source CSV) |
| `internal_temperature` | `FLOAT` | NULL | Indoor temperature (°C) |
| `internal_humidity` | `FLOAT` | NULL | Indoor relative humidity (%) |
| `external_temperature` | `FLOAT` | NULL | Outdoor temperature (°C) — unified from source columns |
| `external_humidity` | `FLOAT` | NULL | Outdoor relative humidity (%) |

---

## 3. Constraints & Indexes
1. **Primary Keys & Clustered Index:**
   - `PK_Households (household_id)`: Clustered Primary Key on `dbo.Households`.
   - `PK_ElectricityReadings (household_id, reading_time)`: Composite Primary Key on `dbo.ElectricityReadings` (creates the default Clustered Index on `(household_id, reading_time)` and prevents duplicate readings per house).
2. **Foreign Key:**
   - `FK_Readings_Households`: Links `ElectricityReadings.household_id` to `Households.household_id`.
3. **Non-Clustered Index:**
   - `IX_Readings_Time`: Explicitly defined as `NONCLUSTERED INDEX` on `dbo.ElectricityReadings(reading_time)` to accelerate time-range analytical queries across households. (The redundant index on `(household_id, reading_time)` was removed since the Composite PK already covers that key order).

---

## 4. Data Loading Pipeline (`load_data.py`)
- **Source CSV Files & Record Counts:**
  - `House_01_cleaned.csv`: **42,432** records
  - `House_03_cleaned.csv`: **42,861** records
  - `House_04_cleaned.csv`: **34,082** records
  - **Total Unified Records:** **119,375** records
- **Adding `household_id`:** Tags each DataFrame with its corresponding `household_id` (`House_01`, `House_03`, `House_04`) prior to concatenation.
- **Column Name Unification:** Resolves schema drift in `House_01_cleaned.csv` where outdoor temperature appeared in both `external_temparature` (typo) and `external_temperature` by merging them via `combine_first()` into `external_temperature`.
- **Timestamp Conversion:** Renames `timestamp` to `reading_time` and converts values to `DATETIME2(0)` via `pd.to_datetime()`.
- **SQL Server Connection & Atomic Loading:** Connects via `SQLAlchemy` + `pyodbc` (`ODBC Driver 17 for SQL Server`, `fast_executemany=True`) and loads both `dbo.Households` and `dbo.ElectricityReadings` (`chunksize=5000`) inside a single atomic transaction (`with engine.begin() as conn:`).
- **Post-Load Count Verification in Python:** Executes `SELECT COUNT(*) FROM dbo.ElectricityReadings` immediately after the transaction commits to verify that all 119,375 rows are stored in SQL Server.

---

## 5. Data Quality & Validation Framework

### A. Pre-Load Validation in Python (`load_data.py`)
Executed on the combined CSV DataFrame **before** inserting into SQL Server:
1. **Required Columns Check:** Verifies that all 15 expected columns are present (`set(expected_columns) - set(df_combined.columns)`), raising a `ValueError` if any column is missing.
2. **Pre-Load Row Count Check:** Confirms the combined dataset contains exactly 119,375 rows.
3. **Pre-Load NULL Timestamp Check:** Ensures `reading_time` has `0` missing values before hitting the `NOT NULL` database constraint.
4. **Pre-Load Duplicate Key Check:** Ensures `0` duplicate `(household_id, reading_time)` rows exist in the CSV files before hitting the Composite Primary Key constraint.

### B. Post-Load Verification in SQL Server (`02_data_quality_checks.sql`)
Executed inside SQL Server **after** loading to verify table integrity and time-series regularity:
1. **Total Record Count Check:** Verifies `COUNT(*) = 119,375` (`PASSED`).
2. **Per-Household Record Count (`LEFT JOIN`):** Joins from `dbo.Households` (`LEFT JOIN dbo.ElectricityReadings`) to ensure no expected household is missing (`House_01` = 42,432, `House_03` = 42,861, `House_04` = 34,082 — `PASSED`).
3. **Post-Load Duplicate Key Check:** Confirms `0` duplicate `(household_id, reading_time)` pairs (`PASSED`).
4. **NULL Values Audit:** Audits `reading_time` (`0` NULLs) and sensor columns across each household (`PASSED`).
5. **Negative Power Check:** Confirms `0` negative power readings across `P_agg` and all sub-metered appliances (`PASSED`).
6. **15-Minute Time Interval Continuity Check:** Uses `LAG(reading_time)` and `DATEDIFF(MINUTE, ...)` to verify 15-minute interval regularity across each household before relying on `0.25h` energy conversion and time-series window functions.

---

## 6. Module Structure
```
src/database/
├── 01_create_database.sql        # Database, tables, constraints, and nonclustered index
├── 02_data_quality_checks.sql    # Post-load SQL validation & interval continuity checks
├── 03_analytical_views.sql       # KPI & ML Feature Store views (gap-aware LAG/LEAD)
├── 04_business_insights.sql      # Analytical queries & business insights
├── load_data.py                  # Python ETL & pre-load validation script
├── README.md                     # Quick schema, loading, and validation overview
└── Docs/
    └── database_documentation.md # Detailed technical documentation
```
