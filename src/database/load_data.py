import os
import pandas as pd
from sqlalchemy import create_engine, text

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(os.path.dirname(base_dir))
    data_dir = os.path.join(project_root, 'data')
    if not os.path.exists(os.path.join(data_dir, 'House_01_cleaned.csv')):
        data_dir = base_dir

    df_01 = pd.read_csv(os.path.join(data_dir, 'House_01_cleaned.csv'))
    df_03 = pd.read_csv(os.path.join(data_dir, 'House_03_cleaned.csv'))
    df_04 = pd.read_csv(os.path.join(data_dir, 'House_04_cleaned.csv'))

    df_01['household_id'] = 'House_01'
    df_03['household_id'] = 'House_03'
    df_04['household_id'] = 'House_04'

    if 'external_temparature' in df_01.columns:
        df_01['external_temperature'] = df_01['external_temperature'].combine_first(df_01['external_temparature'])
        df_01.drop(columns=['external_temparature'], inplace=True)

    df = pd.concat([df_01, df_03, df_04], ignore_index=True)
    df.rename(columns={'timestamp': 'reading_time'}, inplace=True)
    df['reading_time'] = pd.to_datetime(df['reading_time'])

    expected_cols = [
        'household_id', 'reading_time', 'V', 'A', 'P_agg',
        'ac_1', 'ac_2', 'boiler', 'fridge', 'washing_machine',
        'issues', 'internal_temperature', 'internal_humidity',
        'external_temperature', 'external_humidity'
    ]
    missing = set(expected_cols) - set(df.columns)
    if missing:
        raise ValueError(f"Missing columns: {missing}")
    df = df[expected_cols]

    if df['reading_time'].isnull().any() or df.duplicated(subset=['household_id', 'reading_time']).any():
        raise ValueError("Data quality check failed: NULL timestamps or duplicate keys found.")

    engine = create_engine(
        "mssql+pyodbc://localhost/ElectricityDB?driver=ODBC+Driver+17+for+SQL+Server&trusted_connection=yes",
        fast_executemany=True
    )

    df_households = pd.DataFrame([
        {'household_id': 'House_01', 'source_file': 'House_01_cleaned.csv', 'description': 'Smart Residence 01'},
        {'household_id': 'House_03', 'source_file': 'House_03_cleaned.csv', 'description': 'Smart Residence 03'},
        {'household_id': 'House_04', 'source_file': 'House_04_cleaned.csv', 'description': 'Smart Residence 04'},
    ])

    with engine.begin() as conn:
        conn.execute(text("DELETE FROM dbo.ElectricityReadings; DELETE FROM dbo.Households;"))
        df_households.to_sql('Households', con=conn, if_exists='append', index=False)
        df.to_sql('ElectricityReadings', con=conn, if_exists='append', index=False, chunksize=5000)

    with engine.connect() as conn:
        count = conn.execute(text("SELECT COUNT(*) FROM dbo.ElectricityReadings")).scalar_one()
        if count != 119375:
            raise ValueError(f"Expected 119375 rows, found {count}")
        print(f"Successfully loaded and verified {count:,} records.")

if __name__ == "__main__":
    main()
