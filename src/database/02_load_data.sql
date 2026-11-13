-- ============================================================================
-- Project: Smart Energy Analytics & Prediction
-- Script 02: Ingestion & Data Transformation Pipeline (ETL)
-- Engine: Microsoft SQL Server (T-SQL)
-- ============================================================================

USE SmartEnergy_DB;
GO

-- 1. Populate Dimension Table: Dim_House
MERGE INTO dwh.Dim_House AS Target
USING (VALUES 
    ('House_01', 'House 01 - Smart Residence', 'Apartment with 2 ACs, Fridge, Boiler, Washing Machine', 'Athens', 'Greece', 5),
    ('House_03', 'House 03 - Smart Residence', 'Apartment with 2 ACs, Fridge, Boiler, Washing Machine', 'Athens', 'Greece', 5),
    ('House_04', 'House 04 - Smart Residence', 'Apartment with 2 ACs, Fridge, Boiler, Washing Machine', 'Athens', 'Greece', 5)
) AS Source (House_ID, House_Name, Description, City, Country, Monitored_Appliances)
ON Target.House_ID = Source.House_ID
WHEN MATCHED THEN
    UPDATE SET 
        Target.House_Name = Source.House_Name,
        Target.Description = Source.Description,
        Target.Monitored_Appliances = Source.Monitored_Appliances
WHEN NOT MATCHED THEN
    INSERT (House_ID, House_Name, Description, City, Country, Monitored_Appliances)
    VALUES (Source.House_ID, Source.House_Name, Source.Description, Source.City, Source.Country, Source.Monitored_Appliances);

PRINT 'Dimension [dwh.Dim_House] populated successfully.';
GO

-- 2. Clear Previous Staging Data
TRUNCATE TABLE staging.House_01_Raw;
TRUNCATE TABLE staging.House_03_Raw;
TRUNCATE TABLE staging.House_04_Raw;
PRINT 'Staging tables cleared.';
GO

-- 3. Bulk Insert from Cleaned CSV Files into Staging Tables
-- NOTE: Please ensure the CSV files are located in 'C:\بروجيكت سيكول\'
-- If your path differs, update the FROM path accordingly.

PRINT 'Loading House_01_cleaned.csv into staging...';
BULK INSERT staging.House_01_Raw
FROM 'C:\بروجيكت سيكول\House_01_cleaned.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    TABLOCK
);
PRINT 'House_01 loaded to staging: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows.';

PRINT 'Loading House_03_cleaned.csv into staging...';
BULK INSERT staging.House_03_Raw
FROM 'C:\بروجيكت سيكول\House_03_cleaned.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    TABLOCK
);
PRINT 'House_03 loaded to staging: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows.';

PRINT 'Loading House_04_cleaned.csv into staging...';
BULK INSERT staging.House_04_Raw
FROM 'C:\بروجيكت سيكول\House_04_cleaned.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    TABLOCK
);
PRINT 'House_04 loaded to staging: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows.';
GO

-- ============================================================================
-- 4. Transform & Load from Staging to Fact_Energy_Readings
-- ============================================================================

-- Clear fact table before reload to prevent duplicate runs
TRUNCATE TABLE dwh.Fact_Energy_Readings;
PRINT 'Fact table truncated for fresh load.';
GO

-- Load House 01 (Handles the two temperature columns)
INSERT INTO dwh.Fact_Energy_Readings (
    House_ID,
    Reading_Time,
    Voltage,
    Current_A,
    Aggregate_Power,
    AC_1,
    AC_2,
    Boiler,
    Fridge,
    Washing_Machine,
    Internal_Temperature,
    Internal_Humidity,
    External_Temperature,
    External_Humidity,
    Issues_Score
)
SELECT 
    'House_01' AS House_ID,
    TRY_CAST(timestamp AS DATETIME2(0)) AS Reading_Time,
    TRY_CAST(V AS FLOAT) AS Voltage,
    TRY_CAST(A AS FLOAT) AS Current_A,
    TRY_CAST(P_agg AS FLOAT) AS Aggregate_Power,
    TRY_CAST(ac_1 AS FLOAT) AS AC_1,
    TRY_CAST(ac_2 AS FLOAT) AS AC_2,
    TRY_CAST(boiler AS FLOAT) AS Boiler,
    TRY_CAST(fridge AS FLOAT) AS Fridge,
    TRY_CAST(washing_machine AS FLOAT) AS Washing_Machine,
    TRY_CAST(internal_temperature AS FLOAT) AS Internal_Temperature,
    TRY_CAST(internal_humidity AS FLOAT) AS Internal_Humidity,
    -- Prioritize external_temparature (actual sensor), fallback to external_temperature
    COALESCE(TRY_CAST(external_temparature AS FLOAT), TRY_CAST(external_temperature AS FLOAT)) AS External_Temperature,
    TRY_CAST(external_humidity AS FLOAT) AS External_Humidity,
    TRY_CAST(issues AS FLOAT) AS Issues_Score
FROM staging.House_01_Raw
WHERE TRY_CAST(timestamp AS DATETIME2(0)) IS NOT NULL;

PRINT 'Loaded House_01 into Fact table: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows.';
GO

-- Load House 03
INSERT INTO dwh.Fact_Energy_Readings (
    House_ID,
    Reading_Time,
    Voltage,
    Current_A,
    Aggregate_Power,
    AC_1,
    AC_2,
    Boiler,
    Fridge,
    Washing_Machine,
    Internal_Temperature,
    Internal_Humidity,
    External_Temperature,
    External_Humidity,
    Issues_Score
)
SELECT 
    'House_03' AS House_ID,
    TRY_CAST(timestamp AS DATETIME2(0)) AS Reading_Time,
    TRY_CAST(V AS FLOAT) AS Voltage,
    TRY_CAST(A AS FLOAT) AS Current_A,
    TRY_CAST(P_agg AS FLOAT) AS Aggregate_Power,
    TRY_CAST(ac_1 AS FLOAT) AS AC_1,
    TRY_CAST(ac_2 AS FLOAT) AS AC_2,
    TRY_CAST(boiler AS FLOAT) AS Boiler,
    TRY_CAST(fridge AS FLOAT) AS Fridge,
    TRY_CAST(washing_machine AS FLOAT) AS Washing_Machine,
    TRY_CAST(internal_temperature AS FLOAT) AS Internal_Temperature,
    TRY_CAST(internal_humidity AS FLOAT) AS Internal_Humidity,
    TRY_CAST(external_temperature AS FLOAT) AS External_Temperature,
    TRY_CAST(external_humidity AS FLOAT) AS External_Humidity,
    TRY_CAST(issues AS FLOAT) AS Issues_Score
FROM staging.House_03_Raw
WHERE TRY_CAST(timestamp AS DATETIME2(0)) IS NOT NULL;

PRINT 'Loaded House_03 into Fact table: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows.';
GO

-- Load House 04
INSERT INTO dwh.Fact_Energy_Readings (
    House_ID,
    Reading_Time,
    Voltage,
    Current_A,
    Aggregate_Power,
    AC_1,
    AC_2,
    Boiler,
    Fridge,
    Washing_Machine,
    Internal_Temperature,
    Internal_Humidity,
    External_Temperature,
    External_Humidity,
    Issues_Score
)
SELECT 
    'House_04' AS House_ID,
    TRY_CAST(timestamp AS DATETIME2(0)) AS Reading_Time,
    TRY_CAST(V AS FLOAT) AS Voltage,
    TRY_CAST(A AS FLOAT) AS Current_A,
    TRY_CAST(P_agg AS FLOAT) AS Aggregate_Power,
    TRY_CAST(ac_1 AS FLOAT) AS AC_1,
    TRY_CAST(ac_2 AS FLOAT) AS AC_2,
    TRY_CAST(boiler AS FLOAT) AS Boiler,
    TRY_CAST(fridge AS FLOAT) AS Fridge,
    TRY_CAST(washing_machine AS FLOAT) AS Washing_Machine,
    TRY_CAST(internal_temperature AS FLOAT) AS Internal_Temperature,
    TRY_CAST(internal_humidity AS FLOAT) AS Internal_Humidity,
    TRY_CAST(external_temperature AS FLOAT) AS External_Temperature,
    TRY_CAST(external_humidity AS FLOAT) AS External_Humidity,
    TRY_CAST(issues AS FLOAT) AS Issues_Score
FROM staging.House_04_Raw
WHERE TRY_CAST(timestamp AS DATETIME2(0)) IS NOT NULL;

PRINT 'Loaded House_04 into Fact table: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows.';
GO

-- Final Total Verification
SELECT 
    House_ID, 
    COUNT(*) AS Total_Readings,
    MIN(Reading_Time) AS First_Reading,
    MAX(Reading_Time) AS Last_Reading,
    ROUND(AVG(Aggregate_Power), 2) AS Avg_Power_Watts
FROM dwh.Fact_Energy_Readings
GROUP BY House_ID
ORDER BY House_ID;
GO
