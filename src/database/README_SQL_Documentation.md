# Smart Energy Analytics & Prediction - SQL & Database Architecture

## 1. Project Overview & Role
As the **Data Engineer** responsible for the Database & SQL tier, the objective is to design, implement, and maintain a robust, scalable, and high-performance Data Warehouse on **Microsoft SQL Server**.

This database serves as the single source of truth for:
1. **Business Intelligence & Dashboards:** Powering KPIs, peak usage analysis, and appliance breakdown.
2. **Machine Learning & Forecasting:** Providing pre-calculated time and lag features via a dedicated Feature Store view.

---

## 2. Architecture & Data Flow

```
[Cleaned CSV Files]
(House_01, House_03, House_04)
         │
         ▼  BULK INSERT
[Staging Layer (staging.*)]
    ├── staging.House_01_Raw
    ├── staging.House_03_Raw
    └── staging.House_04_Raw
         │
         ▼  ETL Transformations (Type casting, Coalescing schema drift)
[Data Warehouse Layer (dwh.*)]
    ├── Dimension: dwh.Dim_House
    └── Fact:      dwh.Fact_Energy_Readings (Indexed on House_ID & Timestamp)
         │
         ▼  Data Quality & Validation Framework
[Data Quality Checks (03_data_quality_checks.sql)]
         │
         ▼  Serving Layer (Views)
[Analytical Views & Feature Store (dwh.vw_*)]
    ├── vw_House_KPIs            ──> Power BI / Tableau
    ├── vw_Hourly_Peak_Analysis   ──> Dashboard Charts
    ├── vw_Appliance_Breakdown    ──> Donut / Bar Charts
    ├── vw_Temperature_vs_Power   ──> Weather Correlation Visuals
    └── vw_ML_Feature_Store       ──> Python (Scikit-Learn / XGBoost)
```

---

## 3. Data Warehouse Schema Design

### A. Dimension Table: `dwh.Dim_House`
| Column Name | Data Type | Constraints | Description |
|---|---|---|---|
| `House_ID` | `VARCHAR(20)` | PRIMARY KEY | Unique identifier (`House_01`, `House_03`, `House_04`) |
| `House_Name` | `NVARCHAR(100)` | NOT NULL | Friendly display name |
| `Description` | `NVARCHAR(255)` | NULL | Apartment description & equipment |
| `City` | `NVARCHAR(100)` | DEFAULT 'Athens' | Location city |
| `Country` | `NVARCHAR(100)` | DEFAULT 'Greece' | Location country |
| `Monitored_Appliances` | `INT` | DEFAULT 5 | Number of individual sub-metered appliances |
| `Created_At` | `DATETIME2` | DEFAULT SYSDATETIME() | Record creation timestamp |

### B. Fact Table: `dwh.Fact_Energy_Readings`
Contains ~120,000 readings recorded at 15-minute intervals between July 2022 and September 2023.

| Column Name | Data Type | Constraints | Description |
|---|---|---|---|
| `Reading_ID` | `BIGINT` | IDENTITY(1,1), PK | Surrogate primary key |
| `House_ID` | `VARCHAR(20)` | NOT NULL, FK | Reference to `dwh.Dim_House(House_ID)` |
| `Reading_Time` | `DATETIME2(0)` | NOT NULL | Timestamp of observation |
| `Voltage` | `FLOAT` | NULL | Grid voltage (Volts) |
| `Current_A` | `FLOAT` | NULL | Total current (Amperes) |
| `Aggregate_Power` | `FLOAT` | NULL | Total active power (Watts) |
| `AC_1` | `FLOAT` | NULL | Air conditioner unit 1 power (Watts) |
| `AC_2` | `FLOAT` | NULL | Air conditioner unit 2 power (Watts) |
| `Boiler` | `FLOAT` | NULL | Electric water heater power (Watts) |
| `Fridge` | `FLOAT` | NULL | Refrigerator power (Watts) |
| `Washing_Machine` | `FLOAT` | NULL | Washing machine power (Watts) |
| `Internal_Temperature`| `FLOAT` | NULL | Indoor temperature (°C) |
| `Internal_Humidity` | `FLOAT` | NULL | Indoor relative humidity (%) |
| `External_Temperature`| `FLOAT` | NULL | Outdoor ambient temperature (°C) |
| `External_Humidity` | `FLOAT` | NULL | Outdoor ambient humidity (%) |
| `Issues_Score` | `FLOAT` | NULL | Sensor quality metric |

### C. Performance Indexing
- **`IX_Fact_Energy_House_Time`**: Non-clustered index on `(House_ID, Reading_Time)` with covering columns `(Aggregate_Power, External_Temperature, AC_1, AC_2, Fridge, Boiler)`. Enables sub-millisecond range queries.
- **`IX_Fact_Energy_Time`**: Non-clustered index on `(Reading_Time)` for cross-house temporal aggregations.

---

## 4. Key Engineering Highlights & Solutions

1. **Schema Drift Handling:**
   - In `House_01_cleaned.csv`, two columns existed: `external_temparature` (typo with raw values) and `external_temperature` (median filled).
   - Our ETL pipeline resolved this using:
     ```sql
     COALESCE(TRY_CAST(external_temparature AS FLOAT), TRY_CAST(external_temperature AS FLOAT)) AS External_Temperature
     ```
     ensuring complete schema consistency with `House_03` and `House_04`.

2. **Window Functions & Lag Feature Engineering in SQL:**
   - Instead of computing historical features slowly in Python, `dwh.vw_ML_Feature_Store` uses SQL Server Window Functions (`LAG`, `LEAD`, and `AVG OVER ROWS PRECEDING`) to calculate:
     - `Lag_15m_Power` (consumption 1 reading prior).
     - `Lag_1h_Power` (consumption 4 readings prior).
     - `Lag_24h_Power` (consumption 96 readings prior - yesterday same time).
     - `Rolling_1h_Avg_Power` (moving average over the past hour).
     - `Target_Next_15m_Power` (the forecasting target variable).

---

## 5. Execution Guide in SSMS (Step-by-Step)

Open **SQL Server Management Studio (SSMS)**, connect to your server instance, and execute the scripts in order:

1. **Open & Execute `01_create_database_and_tables.sql`:**
   - Creates the database `SmartEnergy_DB`.
   - Creates schemas `staging` and `dwh`.
   - Creates `dwh.Dim_House` and `dwh.Fact_Energy_Readings` with indexes.

2. **Open & Execute `02_load_data.sql`:**
   - Populates dimension data.
   - Bulk inserts CSV files into staging.
   - Transforms and loads 119,378 rows into `dwh.Fact_Energy_Readings`.

3. **Open & Execute `03_data_quality_checks.sql`:**
   - Validates row counts, checks for duplicates, inspects nulls, and verifies electrical boundaries.

4. **Open & Execute `04_analytical_views_and_marts.sql`:**
   - Builds views for BI and the Machine Learning Feature Store.

5. **Open & Execute `05_business_queries_answers.sql`:**
   - Runs queries that directly answer the core questions of the project.
