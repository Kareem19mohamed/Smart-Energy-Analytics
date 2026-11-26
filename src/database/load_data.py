import os
import pandas as pd
from sqlalchemy import create_engine, text, inspect
from sqlalchemy.engine import URL

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

EXPECTED_COLUMNS = [
    'household_id', 'reading_time', 'V', 'A', 'P_agg',
    'ac_1', 'ac_2', 'boiler', 'fridge', 'washing_machine',
    'issues', 'internal_temperature', 'internal_humidity',
    'external_temperature', 'external_humidity'
]

EXPECTED_COUNTS = {
    'House_01': 42432,
    'House_03': 42861,
    'House_04': 34082,
}

SOURCE_FILES = {house: f"{house}_cleaned.csv" for house in EXPECTED_COUNTS}


def resolve_data_dir() -> str:
    env_dir = os.getenv("DATA_DIR")
    if env_dir:
        return env_dir
    candidates = [
        os.path.join(PROJECT_ROOT, 'data', 'cleaned'),
        os.path.join(PROJECT_ROOT, 'data'),
        os.path.join(PROJECT_ROOT, 'data', 'processed'),
    ]
    for folder in candidates:
        if os.path.exists(os.path.join(folder, 'House_01_cleaned.csv')):
            return folder
    return os.path.join(PROJECT_ROOT, 'data', 'cleaned')


def get_staging_dir() -> str:
    stage = os.getenv("STAGING_DIR") or os.path.join(PROJECT_ROOT, 'data', 'staging')
    os.makedirs(stage, exist_ok=True)
    return stage


def get_engine():
    query = {
        "driver": os.getenv("SQL_DRIVER", "ODBC Driver 17 for SQL Server"),
        "TrustServerCertificate": "yes",
    }
    user = os.getenv("SQL_USER")
    if not user:
        query["trusted_connection"] = "yes"
    url = URL.create(
        "mssql+pyodbc",
        username=user,
        password=os.getenv("SQL_PASSWORD"),
        host=os.getenv("SQL_SERVER", "localhost"),
        port=int(os.getenv("SQL_PORT", "1433")),
        database=os.getenv("SQL_DATABASE", "ElectricityDB"),
        query=query,
    )
    return create_engine(url, fast_executemany=True)


def prepare_and_validate_house(df: pd.DataFrame, household_id: str) -> pd.DataFrame:
    df['household_id'] = household_id
    if 'external_temparature' in df.columns and 'external_temperature' in df.columns:
        df['external_temperature'] = df['external_temperature'].combine_first(df['external_temparature'])
        df.drop(columns=['external_temparature'], inplace=True)
    elif 'external_temparature' in df.columns:
        df.rename(columns={'external_temparature': 'external_temperature'}, inplace=True)
    if 'timestamp' in df.columns:
        df.rename(columns={'timestamp': 'reading_time'}, inplace=True)

    missing_columns = set(EXPECTED_COLUMNS) - set(df.columns)
    if missing_columns:
        raise ValueError(f"{household_id} is missing required columns: {missing_columns}")

    expected_rows = EXPECTED_COUNTS[household_id]
    if len(df) != expected_rows:
        raise ValueError(f"{household_id} row count mismatch: expected {expected_rows}, got {len(df)}")

    return df[EXPECTED_COLUMNS]


# ---------------------------------------------------------------- EXTRACT
def extract():
    """Read the cleaned CSV of each house and save it to the staging folder."""
    data_dir = resolve_data_dir()
    stage = get_staging_dir()
    for house_id, filename in SOURCE_FILES.items():
        df = pd.read_csv(os.path.join(data_dir, filename))
        print(f"{house_id}: extracted {len(df):,} rows")
        df.to_csv(os.path.join(stage, f"raw_{house_id}.csv"), index=False)


# -------------------------------------------------------------- TRANSFORM
def transform():
    """Fix column names, validate each house, merge them and run checks."""
    stage = get_staging_dir()
    dfs = []
    for house_id in SOURCE_FILES:
        df = pd.read_csv(os.path.join(stage, f"raw_{house_id}.csv"))
        dfs.append(prepare_and_validate_house(df, house_id))

    df_combined = pd.concat(dfs, ignore_index=True)
    df_combined['reading_time'] = pd.to_datetime(df_combined['reading_time'])

    expected_total = sum(EXPECTED_COUNTS.values())
    if len(df_combined) != expected_total:
        raise ValueError(f"Expected {expected_total} total records, got {len(df_combined)}")

    null_ts = df_combined['reading_time'].isnull().sum()
    dup_keys = df_combined.duplicated(subset=['household_id', 'reading_time']).sum()
    if null_ts > 0 or dup_keys > 0:
        raise ValueError(f"Validation failed: {null_ts} NULL timestamps, {dup_keys} duplicates.")

    df_combined.to_csv(os.path.join(stage, "transformed.csv"), index=False)
    print(f"Transformed {len(df_combined):,} records, 0 NULL timestamps, 0 duplicates.")


# ------------------------------------------------------------------- LOAD
def load():
    """Write the transformed data into SQL Server."""
    stage = get_staging_dir()
    df_combined = pd.read_csv(os.path.join(stage, "transformed.csv"), parse_dates=['reading_time'])

    df_households = pd.DataFrame([
        {'household_id': h, 'source_file': f, 'description': f"Smart Residence {h[-2:]}"}
        for h, f in SOURCE_FILES.items()
    ])

    engine = get_engine()
    inspector = inspect(engine)
    with engine.begin() as conn:
        if inspector.has_table('ElectricityReadings', schema='dbo'):
            conn.execute(text("DELETE FROM dbo.ElectricityReadings"))
        if inspector.has_table('Households', schema='dbo'):
            conn.execute(text("DELETE FROM dbo.Households"))
        df_households.to_sql('Households', con=conn, schema='dbo', if_exists='append', index=False)
        df_combined.to_sql('ElectricityReadings', con=conn, schema='dbo',
                           if_exists='append', index=False, chunksize=5000)
    print(f"Loaded {len(df_combined):,} records into SQL Server.")


# ----------------------------------------------------------------- VERIFY
def verify():
    """Check the counts inside SQL Server against the expected counts."""
    expected_total = sum(EXPECTED_COUNTS.values())
    engine = get_engine()
    with engine.connect() as conn:
        total_count = conn.execute(text("SELECT COUNT(*) FROM dbo.ElectricityReadings")).scalar_one()
        if total_count != expected_total:
            raise ValueError(f"Expected {expected_total} rows in SQL Server, found {total_count}")
        rows = conn.execute(
            text("SELECT household_id, COUNT(*) FROM dbo.ElectricityReadings GROUP BY household_id")
        ).fetchall()
    db_counts = {row[0]: row[1] for row in rows}
    for house_id, expected_rows in EXPECTED_COUNTS.items():
        if db_counts.get(house_id, 0) != expected_rows:
            raise ValueError(f"Count mismatch for {house_id}: expected {expected_rows}, found {db_counts.get(house_id, 0)}")
    print(f"Verified {total_count:,} total records and per-household counts.")


def main():
    extract()
    transform()
    load()
    verify()


if __name__ == "__main__":
    main()