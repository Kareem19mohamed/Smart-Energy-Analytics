import os
import pandas as pd
from sqlalchemy import create_engine, text

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


def resolve_data_dir() -> str:
    base_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(os.path.dirname(base_dir))
    for folder in [os.path.join(project_root, 'data'), os.path.join(project_root, 'data', 'processed'), base_dir]:
        if os.path.exists(os.path.join(folder, 'House_01_cleaned.csv')):
            return folder
    return os.path.join(project_root, 'data')


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


def main():
    data_dir = resolve_data_dir()
    files = {
        'House_01': os.path.join(data_dir, 'House_01_cleaned.csv'),
        'House_03': os.path.join(data_dir, 'House_03_cleaned.csv'),
        'House_04': os.path.join(data_dir, 'House_04_cleaned.csv'),
    }

    dfs = []
    for house_id, path in files.items():
        df_house = pd.read_csv(path)
        print(f"{house_id}: {len(df_house):,} rows")
        dfs.append(prepare_and_validate_house(df_house, house_id))

    df_combined = pd.concat(dfs, ignore_index=True)
    df_combined['reading_time'] = pd.to_datetime(df_combined['reading_time'])

    expected_total = sum(EXPECTED_COUNTS.values())
    if len(df_combined) != expected_total:
        raise ValueError(f"Expected {expected_total} total records before load, got {len(df_combined)}")

    null_ts = df_combined['reading_time'].isnull().sum()
    dup_keys = df_combined.duplicated(subset=['household_id', 'reading_time']).sum()
    if null_ts > 0 or dup_keys > 0:
        raise ValueError(f"Pre-load validation failed: {null_ts} NULL timestamps, {dup_keys} duplicates.")
    print(f"Pre-load validation passed: {len(df_combined):,} total records, 0 NULL timestamps, 0 duplicates.")

    server_name = os.getenv("SQL_SERVER", "localhost")
    engine = create_engine(
        f"mssql+pyodbc://{server_name}/ElectricityDB?driver=ODBC+Driver+17+for+SQL+Server&trusted_connection=yes",
        fast_executemany=True
    )
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))

    df_households = pd.DataFrame([
        {'household_id': 'House_01', 'source_file': 'House_01_cleaned.csv', 'description': 'Smart Residence 01'},
        {'household_id': 'House_03', 'source_file': 'House_03_cleaned.csv', 'description': 'Smart Residence 03'},
        {'household_id': 'House_04', 'source_file': 'House_04_cleaned.csv', 'description': 'Smart Residence 04'},
    ])

    with engine.begin() as conn:
        conn.execute(text("DELETE FROM dbo.ElectricityReadings"))
        conn.execute(text("DELETE FROM dbo.Households"))
        df_households.to_sql('Households', con=conn, if_exists='append', index=False)
        df_combined.to_sql('ElectricityReadings', con=conn, if_exists='append', index=False, chunksize=5000)

    with engine.connect() as conn:
        total_count = conn.execute(text("SELECT COUNT(*) FROM dbo.ElectricityReadings")).scalar_one()
        if total_count != expected_total:
            raise ValueError(f"Expected {expected_total} rows in SQL Server, found {total_count}")

        rows = conn.execute(
            text("SELECT household_id, COUNT(*) AS cnt FROM dbo.ElectricityReadings GROUP BY household_id")
        ).fetchall()
        db_counts = {row[0]: row[1] for row in rows}
        for house_id, expected_rows in EXPECTED_COUNTS.items():
            actual_rows = db_counts.get(house_id, 0)
            if actual_rows != expected_rows:
                raise ValueError(f"Post-load count mismatch for {house_id}: expected {expected_rows}, found {actual_rows}")

    print(f"Successfully validated {total_count:,} total records and per-household counts in SQL Server.")


if __name__ == "__main__":
    main()
