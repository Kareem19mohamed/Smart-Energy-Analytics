"""
============================================================================
Project: Electricity Consumption Analysis & Prediction
Part 3: Database & SQL - Python Data Preparation and Loading Pipeline
Author: Data Engineering Team
============================================================================
This script performs:
1. Reads the 3 CSV files (House_01, House_03, House_04).
2. Adds the 'household_id' column to each dataset.
3. Unifies column names using combine_first() for external temperature.
4. Concatenates the datasets into a single DataFrame of 119,375 records.
5. Connects to Microsoft SQL Server (ElectricityDB) using SQLAlchemy / pyodbc.
6. Populates the 'Households' parent table.
7. Loads the combined readings into 'ElectricityReadings' using to_sql(if_exists='append').
============================================================================
"""

import os
import pandas as pd
from sqlalchemy import create_engine, text

def main():
    print("=" * 60)
    print("  STARTING ELECTRICITY DATA PREPARATION & LOADING PIPELINE")
    print("=" * 60)

    # -------------------------------------------------------------------------
    # Step 1: Locate and Read CSV Files
    # -------------------------------------------------------------------------
    base_dir = os.path.dirname(os.path.abspath(__file__))
    
    # We prioritize the cleaned CSV files available in the directory
    files = {
        'House_01': os.path.join(base_dir, 'House_01_cleaned.csv'),
        'House_03': os.path.join(base_dir, 'House_03_cleaned.csv'),
        'House_04': os.path.join(base_dir, 'House_04_cleaned.csv'),
    }

    print("\n[Step 1] Reading CSV Files with Pandas...")
    df_house_01 = pd.read_csv(files['House_01'])
    df_house_03 = pd.read_csv(files['House_03'])
    df_house_04 = pd.read_csv(files['House_04'])

    print(f" - House_01 rows: {len(df_house_01):,}")
    print(f" - House_03 rows: {len(df_house_03):,}")
    print(f" - House_04 rows: {len(df_house_04):,}")

    # -------------------------------------------------------------------------
    # Step 2: Add 'household_id' column (Stage 9)
    # -------------------------------------------------------------------------
    print("\n[Step 2] Adding 'household_id' identifier to each DataFrame...")
    df_house_01['household_id'] = 'House_01'
    df_house_03['household_id'] = 'House_03'
    df_house_04['household_id'] = 'House_04'

    # -------------------------------------------------------------------------
    # Step 3: Column Name Unification using combine_first() (Stage 10)
    # -------------------------------------------------------------------------
    print("\n[Step 3] Handling 'external_temparature' typo in House_01 using combine_first()...")
    if 'external_temparature' in df_house_01.columns and 'external_temperature' in df_house_01.columns:
        # Combine the two columns into a single unified column
        df_house_01['external_temperature'] = df_house_01['external_temperature'].combine_first(df_house_01['external_temparature'])
        df_house_01.drop(columns=['external_temparature'], inplace=True)
        print(" -> Resolved typo: combined into 'external_temperature' and removed typo column.")
    elif 'external_temparature' in df_house_01.columns:
        df_house_01.rename(columns={'external_temparature': 'external_temperature'}, inplace=True)

    # -------------------------------------------------------------------------
    # Step 4: Concatenate into Single DataFrame (Stage 11)
    # -------------------------------------------------------------------------
    print("\n[Step 4] Concatenating the 3 DataFrames using pd.concat()...")
    df_combined = pd.concat([df_house_01, df_house_03, df_house_04], ignore_index=True)

    # Rename timestamp to reading_time (as specified in Stage 6)
    if 'timestamp' in df_combined.columns:
        df_combined.rename(columns={'timestamp': 'reading_time'}, inplace=True)

    # Convert reading_time to datetime
    df_combined['reading_time'] = pd.to_datetime(df_combined['reading_time'])

    total_records = len(df_combined)
    print(f" -> Total combined records: {total_records:,}")
    assert total_records == 119375, f"Expected 119,375 records, but got {total_records}"

    # Reorder columns to match SQL table definition
    expected_columns = [
        'household_id', 'reading_time', 'V', 'A', 'P_agg', 
        'ac_1', 'ac_2', 'boiler', 'fridge', 'washing_machine', 
        'issues', 'internal_temperature', 'internal_humidity', 
        'external_temperature', 'external_humidity'
    ]
    df_combined = df_combined[[col for col in expected_columns if col in df_combined.columns]]

    # -------------------------------------------------------------------------
    # Step 5: Database Connection (Stage 12 & 13)
    # -------------------------------------------------------------------------
    print("\n[Step 5] Connecting to SQL Server [ElectricityDB]...")
    
    # Connection string for local SQL Server with Windows Authentication
    # Supports both localhost and dot (.)
    connection_string = (
        "mssql+pyodbc://localhost/ElectricityDB?"
        "driver=ODBC+Driver+17+for+SQL+Server&"
        "trusted_connection=yes"
    )
    
    try:
        engine = create_engine(connection_string, fast_executemany=True)
        with engine.connect() as conn:
            result = conn.execute(text("SELECT @@VERSION")).fetchone()
            print(f" -> Successfully connected to SQL Server!")
    except Exception as e:
        print(f"Connection failed: {e}")
        print("Retrying with server name '.' instead of 'localhost'...")
        connection_string = (
            "mssql+pyodbc://./ElectricityDB?"
            "driver=ODBC+Driver+17+for+SQL+Server&"
            "trusted_connection=yes"
        )
        engine = create_engine(connection_string, fast_executemany=True)

    # -------------------------------------------------------------------------
    # Step 6: Populate Households Parent Table (Stage 14)
    # -------------------------------------------------------------------------
    print("\n[Step 6] Populating parent table [Households]...")
    df_households = pd.DataFrame([
        {'household_id': 'House_01', 'source_file': 'House_01.csv', 'description': 'Residence with 2 AC units, boiler, fridge, washing machine'},
        {'household_id': 'House_03', 'source_file': 'House_03.csv', 'description': 'Residence with 2 AC units, boiler, fridge, washing machine'},
        {'household_id': 'House_04', 'source_file': 'House_04.csv', 'description': 'Residence with 2 AC units, boiler, fridge, washing machine'},
    ])

    with engine.begin() as conn:
        # Clear existing data to ensure clean load
        conn.execute(text("DELETE FROM dbo.ElectricityReadings;"))
        conn.execute(text("DELETE FROM dbo.Households;"))
        
        df_households.to_sql(
            name='Households',
            con=conn,
            if_exists='append',
            index=False
        )
    print(" -> [Households] populated with 3 records.")

    # -------------------------------------------------------------------------
    # Step 7: Batch Load into ElectricityReadings Table (Stage 14)
    # -------------------------------------------------------------------------
    print(f"\n[Step 7] Loading {total_records:,} records into [ElectricityReadings] table...")
    print(" -> Using chunksize=5000 and if_exists='append'...")
    
    with engine.begin() as conn:
        df_combined.to_sql(
            name='ElectricityReadings',
            con=conn,
            if_exists='append',
            index=False,
            chunksize=5000
        )

    print(" -> All 119,375 records successfully loaded into [ElectricityReadings]!")

    # -------------------------------------------------------------------------
    # Step 8: Final Validation Check
    # -------------------------------------------------------------------------
    print("\n[Step 8] Verification query from SQL Server:")
    with engine.connect() as conn:
        df_check = pd.read_sql(
            "SELECT household_id, COUNT(*) AS Total_Readings, "
            "MIN(reading_time) AS Min_Time, MAX(reading_time) AS Max_Time, "
            "ROUND(AVG(P_agg), 2) AS Avg_Power_Watts "
            "FROM dbo.ElectricityReadings GROUP BY household_id ORDER BY household_id;",
            con=conn
        )
        print(df_check.to_string(index=False))

    print("\n" + "=" * 60)
    print("  DATA LOADING PIPELINE COMPLETED SUCCESSFULLY!")
    print("=" * 60)

if __name__ == "__main__":
    main()
