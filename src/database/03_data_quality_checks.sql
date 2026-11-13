-- ============================================================================
-- Project: Smart Energy Analytics & Prediction
-- Script 03: Data Quality & Reliability Validation
-- Engine: Microsoft SQL Server (T-SQL)
-- ============================================================================

USE SmartEnergy_DB;
GO

PRINT '=======================================================';
PRINT '   STARTING DATA QUALITY AND INTEGRITY VALIDATION      ';
PRINT '=======================================================';
GO

-- 1. Check Row Counts per House
PRINT '--- Test 1: Record Count per House ---';
SELECT 
    House_ID,
    COUNT(*) AS Total_Records,
    CASE 
        WHEN House_ID = 'House_01' AND COUNT(*) >= 42400 THEN 'PASSED'
        WHEN House_ID = 'House_03' AND COUNT(*) >= 42800 THEN 'PASSED'
        WHEN House_ID = 'House_04' AND COUNT(*) >= 34000 THEN 'PASSED'
        ELSE 'WARNING - Row count mismatch'
    END AS Test_Status
FROM dwh.Fact_Energy_Readings
GROUP BY House_ID;
GO

-- 2. Check for Duplicate Timestamps per House
PRINT '--- Test 2: Duplicate Timestamps Check ---';
WITH DuplicateCheck AS (
    SELECT 
        House_ID,
        Reading_Time,
        COUNT(*) AS Occurrence_Count
    FROM dwh.Fact_Energy_Readings
    GROUP BY House_ID, Reading_Time
    HAVING COUNT(*) > 1
)
SELECT 
    ISNULL(COUNT(*), 0) AS Total_Duplicates,
    CASE 
        WHEN COUNT(*) = 0 THEN 'PASSED: No duplicate timestamps found.'
        ELSE 'FAILED: Found duplicate timestamps!'
    END AS Test_Status
FROM DuplicateCheck;
GO

-- 3. Check for NULL Values in Critical Fields
PRINT '--- Test 3: Null Values in Critical Fields ---';
SELECT 
    House_ID,
    SUM(CASE WHEN Reading_Time IS NULL THEN 1 ELSE 0 END) AS Null_Timestamps,
    SUM(CASE WHEN Aggregate_Power IS NULL THEN 1 ELSE 0 END) AS Null_Aggregate_Power,
    SUM(CASE WHEN Voltage IS NULL THEN 1 ELSE 0 END) AS Null_Voltage,
    SUM(CASE WHEN Current_A IS NULL THEN 1 ELSE 0 END) AS Null_Current,
    SUM(CASE WHEN External_Temperature IS NULL THEN 1 ELSE 0 END) AS Null_Ext_Temp
FROM dwh.Fact_Energy_Readings
GROUP BY House_ID;
GO

-- 4. Check for Negative Power Values (Sensors cannot have negative active power)
PRINT '--- Test 4: Negative Power Values Check ---';
SELECT 
    House_ID,
    SUM(CASE WHEN Aggregate_Power < 0 THEN 1 ELSE 0 END) AS Negative_Agg_Power,
    SUM(CASE WHEN AC_1 < 0 THEN 1 ELSE 0 END) AS Negative_AC1,
    SUM(CASE WHEN AC_2 < 0 THEN 1 ELSE 0 END) AS Negative_AC2,
    SUM(CASE WHEN Boiler < 0 THEN 1 ELSE 0 END) AS Negative_Boiler,
    SUM(CASE WHEN Fridge < 0 THEN 1 ELSE 0 END) AS Negative_Fridge,
    SUM(CASE WHEN Washing_Machine < 0 THEN 1 ELSE 0 END) AS Negative_WashingMachine
FROM dwh.Fact_Energy_Readings
GROUP BY House_ID;
GO

-- 5. Range & Boundary Checks (Voltage, Humidity, Temperature)
PRINT '--- Test 5: Out of Bounds Sensor Values ---';
SELECT 
    House_ID,
    -- Voltage outside 180V - 260V is considered abnormal grid fluctuation
    SUM(CASE WHEN Voltage < 180 OR Voltage > 260 THEN 1 ELSE 0 END) AS Abnormal_Voltage_Count,
    -- Humidity must be between 0% and 100%
    SUM(CASE WHEN External_Humidity < 0 OR External_Humidity > 100 THEN 1 ELSE 0 END) AS Invalid_Ext_Humidity_Count,
    -- Outdoor temperatures outside -10C to 50C in Athens are abnormal
    SUM(CASE WHEN External_Temperature < -10 OR External_Temperature > 50 THEN 1 ELSE 0 END) AS Invalid_Ext_Temp_Count
FROM dwh.Fact_Energy_Readings
GROUP BY House_ID;
GO

-- 6. Energy Conservation Logic Check:
-- Aggregate Power should be >= Sum of sub-metered appliances (with slight tolerance for rounding)
PRINT '--- Test 6: Sub-metered Appliance Energy vs Total Power ---';
SELECT 
    House_ID,
    COUNT(*) AS Total_Readings,
    SUM(CASE 
        WHEN Aggregate_Power + 5 < (ISNULL(AC_1,0) + ISNULL(AC_2,0) + ISNULL(Boiler,0) + ISNULL(Fridge,0) + ISNULL(Washing_Machine,0)) 
        THEN 1 ELSE 0 
    END) AS Readings_Where_Appliances_Exceed_Total,
    ROUND(AVG(Aggregate_Power), 2) AS Avg_Total_Power_Watts,
    ROUND(AVG(ISNULL(AC_1,0) + ISNULL(AC_2,0) + ISNULL(Boiler,0) + ISNULL(Fridge,0) + ISNULL(Washing_Machine,0)), 2) AS Avg_Submetered_Appliances_Watts,
    ROUND(AVG(Aggregate_Power - (ISNULL(AC_1,0) + ISNULL(AC_2,0) + ISNULL(Boiler,0) + ISNULL(Fridge,0) + ISNULL(Washing_Machine,0))), 2) AS Avg_Other_Base_Load_Watts
FROM dwh.Fact_Energy_Readings
GROUP BY House_ID;
GO

PRINT '=======================================================';
PRINT '   DATA QUALITY VALIDATION COMPLETED                  ';
PRINT '=======================================================';
GO
