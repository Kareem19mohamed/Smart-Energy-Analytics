import os
import pandas as pd
from sqlalchemy import create_engine, text

def main():
    print("Starting Electricity Data Ingestion Pipeline...")

    # Step 1: Read CSV files
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

    # Step 2: Add household_id column
    df_house_01['household_id'] = 'House_01'
    df_house_03['household_id'] = 'House_03'
    df_house_04['household_id'] = 'House_04'

    # Step 3: Handle schema drift in House_01 external temperature
    if 'external_temparature' in df_house_01.columns and 'external_temperature' in df_house_01.columns:
        df_house_01['external_temperature'] = df_house_01['external_temperature'].combine_first(df_house_01['external_temparature'])
        df_house_01.drop(columns=['external_temparature'], inplace=True)
    elif 'external_temparature' in df_house_01.columns:
        df_house_01.rename(columns={'external_temparature': 'external_temperature'}, inplace=True)

    # Step 4: Concatenate datasets
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

    # Step 5: Database Connection
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

    # Step 6: Populate Households Dimension Table
    df_households = pd.DataFrame([
        {'household_id': 'House_01', 'source_file': 'House_01.csv', 'description': 'Smart Residence 01'},
        {'household_id': 'House_03', 'source_file': 'House_03.csv', 'description': 'Smart Residence 03'},
        {'household_id': 'House_04', 'source_file': 'House_04.csv', 'description': 'Smart Residence 04'},
    ])

    with engine.begin() as conn:
        conn.execute(text("DELETE FROM dbo.ElectricityReadings;"))
        conn.execute(text("DELETE FROM dbo.Households;"))
        df_households.to_sql(name='Households', con=conn, if_exists='append', index=False)

    # Step 7: Batch Load into ElectricityReadings
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
