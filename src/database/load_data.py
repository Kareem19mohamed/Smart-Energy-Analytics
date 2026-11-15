import os
import sys
import pandas as pd
from sqlalchemy import create_engine, text


def validate_before_load(df: pd.DataFrame, source_name: str) -> None:
    errors = []

    null_timestamps = df['reading_time'].isnull().sum()
    if null_timestamps > 0:
        errors.append(f"{source_name}: {null_timestamps} NULL timestamps found")

    duplicate_count = df.duplicated(subset=['household_id', 'reading_time']).sum()
    if duplicate_count > 0:
        errors.append(f"{source_name}: {duplicate_count} duplicate (household_id, reading_time) pairs found")

    if errors:
        for err in errors:
            print(f"[VALIDATION ERROR] {err}")
        sys.exit("Pipeline aborted: data quality issues found before loading.")

    print(f"[OK] {source_name}: no NULL timestamps, no duplicates")


def main():
    print("Starting Electricity Data Ingestion Pipeline...")

    base_dir = os.path.dirname(os.path.abspath(__file__))

    files = {
        'House_01': os.path.join(base_dir, 'House_01_cleaned.csv'),
        'House_03': os.path.join(base_dir, 'House_03_cleaned.csv'),
        'House_04': os.path.join(base_dir, 'House_04_cleaned.csv'),
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

    total_records = len(df_combined)
    assert total_records == 119375, f"Expected 119,375 records, but got {total_records}"
    print(f"Total unified records: {total_records:,}")

    expected_columns = [
        'household_id', 'reading_time', 'V', 'A', 'P_agg',
        'ac_1', 'ac_2', 'boiler', 'fridge', 'washing_machine',
        'issues', 'internal_temperature', 'internal_humidity',
        'external_temperature', 'external_humidity'
    ]
    df_combined = df_combined[[col for col in expected_columns if col in df_combined.columns]]

    print("\n--- Pre-Load Validation ---")
    validate_before_load(df_combined, "Combined Dataset")
    print("---------------------------\n")

    connection_string = (
        "mssql+pyodbc://localhost/ElectricityDB?"
        "driver=ODBC+Driver+17+for+SQL+Server&"
        "trusted_connection=yes"
    )

    try:
        engine = create_engine(connection_string, fast_executemany=True)
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception:
        connection_string = (
            "mssql+pyodbc://./ElectricityDB?"
            "driver=ODBC+Driver+17+for+SQL+Server&"
            "trusted_connection=yes"
        )
        engine = create_engine(connection_string, fast_executemany=True)

    df_households = pd.DataFrame([
        {'household_id': 'House_01', 'source_file': 'House_01.csv', 'description': 'Smart Residence 01'},
        {'household_id': 'House_03', 'source_file': 'House_03.csv', 'description': 'Smart Residence 03'},
        {'household_id': 'House_04', 'source_file': 'House_04.csv', 'description': 'Smart Residence 04'},
    ])

    with engine.begin() as conn:
        conn.execute(text("DELETE FROM dbo.ElectricityReadings;"))
        conn.execute(text("DELETE FROM dbo.Households;"))
        df_households.to_sql(name='Households', con=conn, if_exists='append', index=False)

    print("Loading readings into ElectricityReadings table...")
    with engine.begin() as conn:
        df_combined.to_sql(
            name='ElectricityReadings',
            con=conn,
            if_exists='append',
            index=False,
            chunksize=5000
        )

    print("Pipeline completed successfully. 119,375 records loaded.")


if __name__ == "__main__":
    main()
