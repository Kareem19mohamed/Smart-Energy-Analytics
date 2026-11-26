# Smart Energy Analytics

A data analytics and forecasting platform for residential energy consumption and environmental conditions across multiple households. Developed as a graduation capstone project under the **Digital Egypt Pioneers Initiative (DEPI)**.

---

## 📌 Project Overview

This project provides an automated end-to-end data pipeline that ingests high-frequency smart meter electrical readings along with environmental/weather sensor datasets, harmonizes their temporal resolutions, and produces clean, unified time-series datasets ready for machine learning forecasting and interactive dashboards.

The pipeline is orchestrated with **Apache Airflow** (running in Docker) and loads the cleaned data into **SQL Server**, where analytical views and queries are built on top of it.

---

## 🏗️ Architecture & Pipeline Design

### Source data

The ETL pipeline starts from **dirty source data**: `data/quality_issues/<house>_with_issues.csv`. These files are prepared once, outside the pipeline, and are stored in the repository. The raw monthly files themselves (`target_houses`) are not stored in the repository.

### Source preparation (outside the DAG)

```
Raw Data (Target Houses)
 │
 ├── house_X/Electric_data/
 │    └── [Monthly CSVs] ──► Exclude Metadata ──► Convert Datetime ──► Resample (15m, mean) ──► Concat
 │                                                                                               │
 └── house_X/Environmental_data/                                                                 ▼
      └── [Monthly CSVs] ──► Exclude Metadata ──► Convert Datetime ──► Set Index ─────────────► Inner Join
                                                                                                 │
                                                                                                 ▼
                                                                           data/processed/<house_X>.csv
                                                                                                 │
                                          inject_quality_issues.py (synthetic issues, fixed seed) ▼
                                                                  data/quality_issues/<house_X>_with_issues.csv
```

These steps are not part of the Airflow DAG and normally do not need to be run again.

### ETL pipeline (Airflow DAG `energy_etl`)

```
extract_source -> clean_data -> stage_cleaned -> transform
               -> create_schema -> load -> verify -> create_views
```

The 8 tasks are grouped into three stages in the Airflow graph:

| Stage | Task | What it does |
|---|---|---|
| EXTRACT | `extract_source` | Reads the dirty source files from `data/quality_issues` and reports the row count of each house. Fails if a file is missing. |
| TRANSFORM | `clean_data` | Removes duplicates, detects outliers and stuck-sensor readings, and fills missing values with the column median. Writes `data/cleaned`. |
| TRANSFORM | `stage_cleaned` | Copies the cleaned files of House_01, House_03 and House_04 to `data/staging`. |
| TRANSFORM | `transform` | Fixes column names, adds `household_id`, validates columns, row counts, NULL timestamps and duplicate keys, and merges the three houses. |
| LOAD | `create_schema` | Runs `01_create_database.sql` (tables, keys, index). Safe to re-run. |
| LOAD | `load` | Writes `Households` and `ElectricityReadings` into SQL Server (`ElectricityDB`). |
| LOAD | `verify` | Compares row counts in SQL Server with the expected counts. |
| LOAD | `create_views` | Runs `03_analytical_views.sql` to (re)create the analytical views. |

Data flow:

```
data/quality_issues (dirty) -> data/cleaned -> data/staging -> SQL Server
```

Only House_01, House_03 and House_04 go through the pipeline. The dirty source has 2 extra duplicate rows per house; after cleaning the counts are 42,432 / 42,861 / 34,082 (119,375 in total).

Note: `clean_data` compares the dirty files with `data/processed` to find the changed values, so that folder must exist.

### Key Engineering Decisions:
1. **Per-Month Resampling**:
   - Electrical sensor readings are resampled to a consistent 15-minute frequency **prior to monthly concatenation**. This prevents edge-boundary averaging distortion if a given month starts or ends with gaps.
2. **Deterministic & Safe Ingestion**:
   - Files are discovered and sorted deterministically across platforms using `pathlib.Path`.
   - Metadata files (`*metadata*`) containing house specifications are automatically filtered out during ingestion to avoid schema collisions.
3. **Temporal Alignment**:
   - Both datasets are aligned on their `pd.DatetimeIndex` via an inner join, creating a strictly synchronized feature set for predictive modeling.
4. **Validation before loading**:
   - `transform` stops the DAG if any check fails, so the database is never touched by bad data. `verify` re-checks the counts inside SQL Server after the load.
5. **Reproducible test data**:
   - The dirty source files were generated with a fixed random seed, so they can be regenerated identically.
6. **Safe re-runs**:
   - `create_schema` uses `IF NOT EXISTS` and `load` replaces the table contents, so the DAG can be triggered again at any time.
7. **Corruption kept outside the ETL**:
   - Injecting issues only simulates a dirty source. It is a one-time preparation step, not part of the pipeline: the DAG pulls the dirty data and cleans it.

---

## 🗄️ Database

SQL scripts live in `src/database`:

| Script | Purpose | How it runs |
|---|---|---|
| `01_create_database.sql` | Database, tables, primary/foreign keys, index | DAG task `create_schema` |
| `02_data_quality_checks.sql` | Post-load checks, each returns PASSED/FAILED | Manually |
| `03_analytical_views.sql` | `vw_Household_KPIs` and `vw_ML_Feature_Store` | DAG task `create_views` |
| `04_business_insights.sql` | Analysis queries: peak hours, appliance share, temperature effect, weekday vs weekend | Manually |

Tables: `dbo.Households` and `dbo.ElectricityReadings` (primary key: `household_id` + `reading_time`). More details: `src/database/README.md` and `src/database/Docs/`.

---

## 📁 Repository Structure

```text
Smart-Energy-Analytics/
├── dags/
│   └── energy_etl_dag.py          # Airflow DAG (8 tasks)
├── data/
│   ├── raw/                       # Placeholder for raw datasets (kept outside Git)
│   ├── processed/                 # Clean per-house CSVs (reference for clean_data)
│   ├── quality_issues/            # Dirty source data: the ETL input
│   ├── cleaned/                   # Output of clean_data
│   └── staging/                   # Temporary files between tasks (not committed)
├── src/
│   ├── data_processing/
│   │   ├── __init__.py
│   │   ├── data_ingestion.py          # File discovery, exclusion & reading
│   │   ├── data_transformation.py     # Resampling & temporal aggregation logic
│   │   ├── inject_quality_issues.py   # Injects synthetic data quality issues
│   │   └── clean_data.py              # Anomaly detection & cleaning
│   ├── database/
│   │   ├── load_data.py               # extract / transform / load / verify functions
│   │   ├── run_sql.py                 # Runs the .sql files (splits them at GO)
│   │   ├── 01_create_database.sql ... 04_business_insights.sql
│   │   ├── README.md
│   │   └── Docs/
│   ├── models/
│   │   └── forecasting.py             # Predictive modeling & load forecasting
│   └── dashboard/
│       └── app.py                     # Visualization application
├── main.py                  # Local entry point: ingest + inject issues + clean
├── Dockerfile               # Airflow image with the SQL Server ODBC driver
├── docker-compose.yml       # Airflow services
├── .env.example             # Template for your local .env (never commit .env)
├── requirements.txt         # Core dependencies
├── .gitignore               # Git exclusion rules
└── README.md                # Project documentation
```

---

## 🚀 Getting Started

### Raw data layout
```text
target_houses/
├── house_1/
│   ├── Electric_data/
│   │   ├── 2023_01.csv
│   │   └── ...
│   └── Environmental_data/
│       ├── 2023_01.csv
│       └── ...
```
The output file takes the name of the house folder. The later steps expect the names `House_01`, `House_03` and `House_04`.

The raw data is not stored in the repository, and the DAG does not need it: it starts from `data/quality_issues`. The raw data is only needed to regenerate `data/processed` (see Option B).

### Option A: Docker + Airflow (recommended)

**Prerequisites**
- Docker Desktop
- SQL Server on your machine with **TCP/IP enabled on port 1433** and **Mixed Mode authentication** (restart the SQL Server service after changing them)
- Windows Firewall rule for port 1433 if the container cannot connect (PowerShell as Administrator):
  ```powershell
  New-NetFirewallRule -DisplayName "SQL Server 1433 Docker" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow
  ```

**1. Create the database and login (once).** Use your own password. The tables are created by the DAG.
```powershell
sqlcmd -S localhost -E -C -Q "CREATE DATABASE ElectricityDB"
sqlcmd -S localhost -E -C -Q "CREATE LOGIN airflow_user WITH PASSWORD='YourPassword', CHECK_POLICY=OFF"
sqlcmd -S localhost -E -C -d ElectricityDB -Q "CREATE USER airflow_user FOR LOGIN airflow_user; ALTER ROLE db_owner ADD MEMBER airflow_user;"
```

**2. Configure.**
```powershell
Copy-Item .env.example .env
```
Edit `.env`: set `SQL_PASSWORD` to your password.

**3. Start.**
```powershell
docker compose build airflow-init
docker compose up -d
```

**4. Run the DAG.** Open http://localhost:8080 (user `admin`, password `admin`, local use only), enable `energy_etl` and click **Trigger DAG**. All 8 tasks should turn green.

**5. Check the result.**
```powershell
sqlcmd -S localhost -E -C -d ElectricityDB -Q "SELECT household_id, COUNT(*) AS cnt FROM dbo.ElectricityReadings GROUP BY household_id"
sqlcmd -S localhost -E -C -d ElectricityDB -Q "SELECT name FROM sys.views"
```
Expected: 42,432 / 42,861 / 34,082 rows and the views `vw_Household_KPIs` and `vw_ML_Feature_Store`.

Optional reports:
```powershell
sqlcmd -S localhost -E -C -W -i src\database\02_data_quality_checks.sql
sqlcmd -S localhost -E -C -W -i src\database\04_business_insights.sql
```

Stop with `docker compose down`.

### Option B: Run locally without Docker

Requires Python 3.10+, Git and the Microsoft ODBC Driver 17 for SQL Server. Create the database first (the `CREATE DATABASE` line from Option A, step 1).

```powershell
git clone https://github.com/your-username/Smart-Energy-Analytics.git
cd Smart-Energy-Analytics
pip install -r requirements.txt

python -c "from src.data_processing import clean_data; clean_data.main()"   # data/quality_issues -> data/cleaned
sqlcmd -S localhost -E -C -i src\database\01_create_database.sql
python src/database/load_data.py                    # stage, transform, load, verify
sqlcmd -S localhost -E -C -i src\database\03_analytical_views.sql
```
Without `SQL_USER` set, `load_data.py` connects to `localhost` with Windows Authentication.

#### Regenerating the source data (optional)

Only needed if `data/processed` or `data/quality_issues` are missing. This needs the raw data: put it in `data/raw` or set `RAW_DATA_DIR`.

```powershell
$env:RAW_DATA_DIR = "C:\path\to\target_houses"
python main.py     # raw -> processed -> quality_issues -> cleaned
```

---

## 🧰 Troubleshooting

| Problem | Fix |
|---|---|
| `Login failed for user 'airflow_user' (18456)` | Wrong password, or the login does not exist. Reset it with `ALTER LOGIN airflow_user WITH PASSWORD='...'` and match `.env`. |
| `create_schema` fails with `Cannot open database "ElectricityDB"` | The database or the `airflow_user` mapping is missing. Run step 1 again. |
| Connection timeout from the container | Check TCP/IP on port 1433 and the firewall rule above. |
| `transform` fails with a row-count mismatch | The data differs from the one `EXPECTED_COUNTS` in `load_data.py` was built on. |
| Import Error at the top of the Airflow page | Open it to read the message. Usually a missing file or a wrong mount in `docker-compose.yml`. |

---

## 🛠️ Tech Stack
- **Language**: Python 3
- **Data Engineering**: Pandas, Pathlib, SQLAlchemy, pyodbc
- **Orchestration**: Apache Airflow (Docker)
- **Storage**: SQL Server (CSV files between pipeline stages)
- **Analytics & Visualization**: SQL views and queries, Matplotlib / Streamlit *(planned)*
- **Machine Learning**: Scikit-Learn / Statsmodels *(planned)*