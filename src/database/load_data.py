import os
import pandas as pd
from sqlalchemy import create_engine, text


def resolve_data_dir() -> str:
    base_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(os.path.dirname(base_dir))
    candidates = [
        os.path.join(project_root, 'data'),
        os.path.join(project_root, 'data', 'processed'),
        base_dir,
    ]
    for folder in candidates:
        if os.path.exists(os.path.join(folder, 'House_01_cleaned.csv')):
            return folder
    return os.path.join(project_root, 'data')


def validate_before_load(df: pd.DataFrame) -> None:
    null_timestamps = df['reading_time'].isnull().sum()
    if null_timestamps > 0:
        raise ValueError(f"Found {null_timestamps} NULL timestamps before loading.")

    duplicate_count = df.duplicated(subset=['household_id', 'reading_time']).sum()
    if duplicate_count > 0:
        raise ValueError(f"Found {duplicate_count} duplicate (household_id, reading_time) rows before loading.")

    print("Pre-load validation passed: 0 NULL timestamps, 0 duplicate keys.")


def main():
    print("Starting Electricity Data Ingestion Pipeline...")

    data_dir = resolve_data_dir()

    files = {
        'House_01': os.path.join(data_dir, 'House_01_cleaned.csv'),
        'House_03': os.path.join(data_dir, 'House_03_cleaned.csv'),
        'House_04': os.path.join(data_dir, 'House_04_cleaned.csv'),
    }

    df_house_01 = pd.read_csv(files['House_01'])
    df_house_03 = pd.read_csv(files['House_03'])
    df_house_04 = pd.read_csv(files['House_04'])

    print(f"House_01: {len(df_house_01):,} rows")
    print(f"House_03: {len(df_house_03):,} rows")
    print(f"House_04: {len(df_house_04):,} rows")

    df_house_01['household_id'] = 'House_01'
    df_house_03['household_id'] = 'House_03'
    df_house_04['household_id'] = 'House_04'

    if 'external_temparature' in df_house_01.columns and 'external_temperature' in df_house_01.columns:
        df_house_01['external_temperature'] = df_house_01['external_temperature'].combine_first(df_house_01['external_temparature'])
        df_house_01.drop(columns=['external_temparature'], inplace=True)
    elif 'external_temparature' in df_house_01.columns:
        df_house_01.rename(columns={'external_temparature': 'external_temperature'}, inplace=True)

    df_combined = pd.concat([df_house_01, df_house_03, df_house_04], ignore_index=True)

    if 'timestamp' in df_combined.columns:
        df_combined.rename(columns={'timestamp': 'reading_time'}, inplace=True)

    df_combined['reading_time'] = pd.to_datetime(df_combined['reading_time'])

    expected_columns = [
        'household_id', 'reading_time', 'V', 'A', 'P_agg',
        'ac_1', 'ac_2', 'boiler', 'fridge', 'washing_machine',
        'issues', 'internal_temperature', 'internal_humidity',
        'external_temperature', 'external_humidity'
    ]

    missing_columns = set(expected_columns) - set(df_combined.columns)
    if missing_columns:
        raise ValueError(f"Missing required columns: {missing_columns}")

    df_combined = df_combined[expected_columns]

    total_records = len(df_combined)
    if total_records != 119375:
        raise ValueError(f"Expected 119,375 records before load, got {total_records}")

    validate_before_load(df_combined)

    server_name = os.getenv("SQL_SERVER", "localhost")
    connection_string = (
        f"mssql+pyodbc://{server_name}/ElectricityDB?"
        "driver=ODBC+Driver+17+for+SQL+Server&"
        "trusted_connection=yes"
    )

    engine = create_engine(connection_string, fast_executemany=True)
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))

    df_households = pd.DataFrame([
        {'household_id': 'House_01', 'source_file': 'House_01_cleaned.csv', 'description': 'Smart Residence 01'},
        {'household_id': 'House_03', 'source_file': 'House_03_cleaned.csv', 'description': 'Smart Residence 03'},
        {'household_id': 'House_04', 'source_file': 'House_04_cleaned.csv', 'description': 'Smart Residence 04'},
    ])

    print("Loading households and readings in a single transaction...")
    with engine.begin() as conn:
        conn.execute(text("DELETE FROM dbo.ElectricityReadings;"))
        conn.execute(text("DELETE FROM dbo.Households;"))
        df_households.to_sql(name='Households', con=conn, if_exists='append', index=False)
        df_combined.to_sql(
            name='ElectricityReadings',
            con=conn,
            if_exists='append',
            index=False,
            chunksize=5000
        )

    with engine.connect() as conn:
        count = conn.execute(
            text("SELECT COUNT(*) FROM dbo.ElectricityReadings")
        ).scalar_one()
        if count != 119375:
            raise ValueError(f"Expected 119375 rows, found {count}")

    print(f"Successfully validated {count:,} records.")


if __name__ == "__main__":
    main()
