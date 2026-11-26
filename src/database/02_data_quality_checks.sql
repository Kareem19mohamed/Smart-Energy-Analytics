USE ElectricityDB;
GO

SELECT 
    COUNT(*) AS Total_Records_In_DB,
    119375 AS Expected_Records,
    CASE WHEN COUNT(*) = 119375 THEN 'PASSED' ELSE 'FAILED' END AS Validation_Status
FROM dbo.ElectricityReadings;
GO

SELECT 
    h.household_id,
    COUNT(r.reading_time) AS Actual_Count,
    CASE h.household_id WHEN 'House_01' THEN 42432 WHEN 'House_03' THEN 42861 WHEN 'House_04' THEN 34082 END AS Expected_Count,
    CASE 
        WHEN h.household_id = 'House_01' AND COUNT(r.reading_time) = 42432 THEN 'PASSED'
        WHEN h.household_id = 'House_03' AND COUNT(r.reading_time) = 42861 THEN 'PASSED'
        WHEN h.household_id = 'House_04' AND COUNT(r.reading_time) = 34082 THEN 'PASSED'
        ELSE 'FAILED'
    END AS Status
FROM dbo.Households h
LEFT JOIN dbo.ElectricityReadings r ON h.household_id = r.household_id
GROUP BY h.household_id
ORDER BY h.household_id;
GO

WITH Duplicates AS (
    SELECT household_id, reading_time, COUNT(*) AS Duplicate_Count
    FROM dbo.ElectricityReadings
    GROUP BY household_id, reading_time
    HAVING COUNT(*) > 1
)
SELECT 
    ISNULL(COUNT(*), 0) AS Total_Duplicates,
    CASE WHEN COUNT(*) = 0 THEN 'PASSED' ELSE 'FAILED' END AS Duplicate_Check_Status
FROM Duplicates;
GO

SELECT 
    household_id,
    COUNT(*) AS Total_Rows,
    SUM(CASE WHEN reading_time IS NULL THEN 1 ELSE 0 END) AS Null_Reading_Time,
    SUM(CASE WHEN P_agg IS NULL THEN 1 ELSE 0 END) AS Null_P_agg,
    SUM(CASE WHEN V IS NULL THEN 1 ELSE 0 END) AS Null_Voltage,
    SUM(CASE WHEN A IS NULL THEN 1 ELSE 0 END) AS Null_Current,
    SUM(CASE WHEN external_temperature IS NULL THEN 1 ELSE 0 END) AS Null_Ext_Temp,
    SUM(CASE WHEN external_humidity IS NULL THEN 1 ELSE 0 END) AS Null_Ext_Humidity,
    SUM(CASE WHEN internal_temperature IS NULL THEN 1 ELSE 0 END) AS Null_Int_Temp,
    SUM(CASE WHEN internal_humidity IS NULL THEN 1 ELSE 0 END) AS Null_Int_Humidity
FROM dbo.ElectricityReadings
GROUP BY household_id
ORDER BY household_id;
GO

SELECT 
    household_id,
    SUM(CASE WHEN P_agg < 0 THEN 1 ELSE 0 END) AS Negative_P_agg,
    SUM(CASE WHEN ac_1 < 0 THEN 1 ELSE 0 END) AS Negative_AC1,
    SUM(CASE WHEN ac_2 < 0 THEN 1 ELSE 0 END) AS Negative_AC2,
    SUM(CASE WHEN boiler < 0 THEN 1 ELSE 0 END) AS Negative_Boiler,
    SUM(CASE WHEN fridge < 0 THEN 1 ELSE 0 END) AS Negative_Fridge,
    SUM(CASE WHEN washing_machine < 0 THEN 1 ELSE 0 END) AS Negative_WashingMachine,
    SUM(CASE WHEN P_agg < 0 OR ac_1 < 0 OR ac_2 < 0 OR boiler < 0 OR fridge < 0 OR washing_machine < 0 THEN 1 ELSE 0 END) AS Rows_With_Negative_Readings
FROM dbo.ElectricityReadings
GROUP BY household_id
ORDER BY household_id;
GO

WITH TimeIntervals AS (
    SELECT 
        household_id,
        DATEDIFF(MINUTE, LAG(reading_time) OVER (PARTITION BY household_id ORDER BY reading_time), reading_time) AS Interval_Minutes
    FROM dbo.ElectricityReadings
)
SELECT 
    household_id,
    COUNT(*) AS Total_Transitions,
    SUM(CASE WHEN Interval_Minutes = 15 THEN 1 ELSE 0 END) AS Regular_15m_Intervals,
    SUM(CASE WHEN Interval_Minutes <> 15 THEN 1 ELSE 0 END) AS Irregular_Gaps_Count,
    MAX(Interval_Minutes) AS Max_Gap_Minutes
FROM TimeIntervals
WHERE Interval_Minutes IS NOT NULL
GROUP BY household_id
ORDER BY household_id;
GO
