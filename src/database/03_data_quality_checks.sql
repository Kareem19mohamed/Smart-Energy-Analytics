USE SmartEnergy_DB;
GO

SELECT 
    House_ID,
    COUNT(*) AS Total_Records,
    CASE 
        WHEN House_ID = 'House_01' AND COUNT(*) >= 42400 THEN 'PASSED'
        WHEN House_ID = 'House_03' AND COUNT(*) >= 42800 THEN 'PASSED'
        WHEN House_ID = 'House_04' AND COUNT(*) >= 34000 THEN 'PASSED'
        ELSE 'FAILED'
    END AS Test_Status
FROM dwh.Fact_Energy_Readings
GROUP BY House_ID;
GO

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
        WHEN COUNT(*) = 0 THEN 'PASSED'
        ELSE 'FAILED'
    END AS Test_Status
FROM DuplicateCheck;
GO

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

SELECT 
    House_ID,
    SUM(CASE WHEN Voltage < 180 OR Voltage > 260 THEN 1 ELSE 0 END) AS Abnormal_Voltage_Count,
    SUM(CASE WHEN External_Humidity < 0 OR External_Humidity > 100 THEN 1 ELSE 0 END) AS Invalid_Ext_Humidity_Count,
    SUM(CASE WHEN External_Temperature < -10 OR External_Temperature > 50 THEN 1 ELSE 0 END) AS Invalid_Ext_Temp_Count
FROM dwh.Fact_Energy_Readings
GROUP BY House_ID;
GO

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
