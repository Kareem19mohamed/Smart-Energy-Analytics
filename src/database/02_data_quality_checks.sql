USE ElectricityDB;
GO

SELECT 
    COUNT(*) AS Total_Records,
    119375 AS Expected_Records,
    CASE WHEN COUNT(*) = 119375 THEN 'PASSED' ELSE 'FAILED' END AS Status
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
GROUP BY h.household_id;
GO

SELECT household_id, reading_time, COUNT(*) AS Duplicate_Count
FROM dbo.ElectricityReadings
GROUP BY household_id, reading_time
HAVING COUNT(*) > 1;
GO

SELECT 
    household_id,
    SUM(CASE WHEN reading_time IS NULL THEN 1 ELSE 0 END) AS Null_Reading_Time,
    SUM(CASE WHEN P_agg IS NULL THEN 1 ELSE 0 END) AS Null_P_agg,
    SUM(CASE WHEN external_temperature IS NULL THEN 1 ELSE 0 END) AS Null_Ext_Temp,
    SUM(CASE WHEN P_agg < 0 OR ac_1 < 0 OR ac_2 < 0 OR boiler < 0 OR fridge < 0 OR washing_machine < 0 THEN 1 ELSE 0 END) AS Negative_Readings
FROM dbo.ElectricityReadings
GROUP BY household_id;
GO

WITH Intervals AS (
    SELECT household_id, DATEDIFF(MINUTE, LAG(reading_time) OVER (PARTITION BY household_id ORDER BY reading_time), reading_time) AS Diff_Min
    FROM dbo.ElectricityReadings
)
SELECT 
    household_id,
    SUM(CASE WHEN Diff_Min = 15 THEN 1 ELSE 0 END) AS Regular_15m_Count,
    SUM(CASE WHEN Diff_Min <> 15 THEN 1 ELSE 0 END) AS Irregular_Gaps_Count
FROM Intervals
WHERE Diff_Min IS NOT NULL
GROUP BY household_id;
GO
