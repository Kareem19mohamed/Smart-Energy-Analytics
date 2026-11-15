# Database Documentation - ElectricityDB

## 1. Schema Overview
Database: `ElectricityDB`  
Engine: Microsoft SQL Server (T-SQL)

The database consists of two relational tables with a One-to-Many (1:N) relationship:
- **Households:** Parent table with `household_id` as the Primary Key.
- **ElectricityReadings:** Child table with a Composite Primary Key `(household_id, reading_time)` and a Foreign Key referencing the `Households` table.

```
[dbo.Households] (Parent)
    │ PK: household_id
    │
    └─── 1 : Many
         │
         ▼
[dbo.ElectricityReadings] (Child)
    PK: (household_id, reading_time)
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

## 3. Data Transformation
Before loading into SQL Server, `load_data.py` performs the following transformations:
1. **Household Identification:** Adds `household_id` (`House_01`, `House_03`, `House_04`) to each corresponding dataset prior to concatenation.
2. **Column Name Unification:** Resolves schema drift in `House_01_cleaned.csv`, where outdoor temperature appeared under both `external_temparature` (typo) and `external_temperature`, merging them into a single `external_temperature` column using `combine_first()`.
3. **Timestamp Standardization:** Renames `timestamp` to `reading_time` and converts values to `DATETIME2(0)` format.
4. **Pre-Load Quality Gate:** Checks the combined DataFrame in Python for NULL timestamps and duplicate `(household_id, reading_time)` pairs before database insertion.

---

## 4. Data Loading
- **Source Files:** `House_01_cleaned.csv` (42,432 rows), `House_03_cleaned.csv` (42,861 rows), `House_04_cleaned.csv` (34,082 rows)
- **Total Records:** 119,375
- **Loading Method:** Python (`pandas` + `SQLAlchemy` with `fast_executemany=True`, `chunksize=5000`)
- **Target Tables:** `dbo.Households` and `dbo.ElectricityReadings`
- **Missing Values:** Preserved as `NULL` where applicable

---

## 5. Data Validation & Constraints
1. **Database Constraints:**
   - **Composite Primary Key:** `PK_ElectricityReadings (household_id, reading_time)` creates the clustered index and prevents duplicate readings per house.
   - **Foreign Key:** `FK_Readings_Households` enforces referential integrity.
   - **Non-Clustered Index:** `IX_Readings_Time` on `reading_time` optimizes cross-household time-range queries.
2. **Post-Load Verification (`02_data_quality_checks.sql`):**
   - Total row count check: **119,375 rows** (`PASSED`)
   - Per-household row count check via `LEFT JOIN` on `dbo.Households`: `House_01` = 42,432, `House_03` = 42,861, `House_04` = 34,082 (`PASSED`)
   - Duplicate `(household_id, reading_time)` check: **0 duplicates** (`PASSED`)
   - NULL timestamp & sensor completeness check: **0 NULL timestamps** (`PASSED`)
   - Negative power values check: **0 negative readings** (`PASSED`)
   - Time-step continuity check (`LAG` interval = 15 minutes): verifies interval regularity for downstream `kWh` and window function calculations.

---

## 6. Module Structure
```
src/database/
├── 01_create_database.sql        # Database, tables, constraints, and index
├── 02_data_quality_checks.sql    # Post-load validation & interval continuity checks
├── 03_analytical_views.sql       # KPI & ML Feature Store views
├── 04_business_insights.sql      # Analytical queries & business insights
├── load_data.py                  # Python ETL & pre-load validation script
├── README.md                     # Quick schema & pipeline overview
└── Docs/
    └── database_documentation.md # Detailed technical documentation
```
