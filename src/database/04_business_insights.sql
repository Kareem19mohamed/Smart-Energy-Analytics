USE ElectricityDB;
GO

SELECT 
    r.household_id,
    COUNT(*) AS Total_Readings,
    DATEDIFF(DAY, MIN(r.reading_time), MAX(r.reading_time)) + 1 AS Total_Monitored_Days,
    ROUND(AVG(r.P_agg), 2) AS Avg_Power_Watts,
    ROUND(SUM(r.P_agg * 0.25 / 1000.0), 2) AS Total_Energy_kWh,
    DENSE_RANK() OVER (ORDER BY SUM(r.P_agg * 0.25 / 1000.0) DESC) AS Total_Energy_Rank,
    DENSE_RANK() OVER (ORDER BY AVG(r.P_agg) DESC) AS Avg_Power_Rank
FROM dbo.ElectricityReadings r
GROUP BY r.household_id
ORDER BY Total_Energy_kWh DESC;
GO

WITH HourlyAvg AS (
    SELECT 
        household_id,
        DATEPART(HOUR, reading_time) AS Hour_Of_Day,
        ROUND(AVG(P_agg), 2) AS Avg_Power_Watts,
        ROUND(AVG(ISNULL(ac_1, 0) + ISNULL(ac_2, 0)), 2) AS Avg_AC_Watts,
        ROUND(AVG(boiler), 2) AS Avg_Boiler_Watts,
        ROUND(AVG(fridge), 2) AS Avg_Fridge_Watts,
        ROUND(AVG(washing_machine), 2) AS Avg_Washing_Watts,
        DENSE_RANK() OVER (PARTITION BY household_id ORDER BY AVG(P_agg) DESC) AS Peak_Rank
    FROM dbo.ElectricityReadings
    GROUP BY household_id, DATEPART(HOUR, reading_time)
)
SELECT 
    household_id, Peak_Rank, Hour_Of_Day, Avg_Power_Watts, Avg_AC_Watts, Avg_Boiler_Watts,
    CASE 
        WHEN Avg_AC_Watts > Avg_Boiler_Watts AND Avg_AC_Watts > Avg_Fridge_Watts AND Avg_AC_Watts > Avg_Washing_Watts THEN 'AC Driven'
        WHEN Avg_Boiler_Watts > Avg_AC_Watts AND Avg_Boiler_Watts > Avg_Fridge_Watts AND Avg_Boiler_Watts > Avg_Washing_Watts THEN 'Water Boiler Driven'
        WHEN Avg_Washing_Watts > Avg_AC_Watts AND Avg_Washing_Watts > Avg_Boiler_Watts AND Avg_Washing_Watts > Avg_Fridge_Watts THEN 'Washing Machine Driven'
        WHEN Avg_Fridge_Watts > Avg_AC_Watts AND Avg_Fridge_Watts > Avg_Boiler_Watts AND Avg_Fridge_Watts > Avg_Washing_Watts THEN 'Fridge Driven'
        ELSE 'Mixed Appliance Activity'
    END AS Primary_Peak_Driver
FROM HourlyAvg
WHERE Peak_Rank <= 3
ORDER BY household_id, Peak_Rank;
GO

SELECT 
    household_id,
    ROUND(SUM(P_agg) * 0.25 / 1000.0, 2) AS Total_kWh,
    ROUND(((ISNULL(SUM(ac_1), 0) + ISNULL(SUM(ac_2), 0)) / NULLIF(SUM(P_agg), 0)) * 100, 2) AS AC_Share_Pct,
    ROUND((ISNULL(SUM(boiler), 0) / NULLIF(SUM(P_agg), 0)) * 100, 2) AS Boiler_Share_Pct,
    ROUND((ISNULL(SUM(fridge), 0) / NULLIF(SUM(P_agg), 0)) * 100, 2) AS Fridge_Share_Pct,
    ROUND((ISNULL(SUM(washing_machine), 0) / NULLIF(SUM(P_agg), 0)) * 100, 2) AS WashingMachine_Share_Pct
FROM dbo.ElectricityReadings
GROUP BY household_id;
GO

WITH TempBrackets AS (
    SELECT P_agg, ISNULL(ac_1, 0) + ISNULL(ac_2, 0) AS AC_Power,
        CASE WHEN external_temperature < 15 THEN 1 WHEN external_temperature < 20 THEN 2 WHEN external_temperature < 25 THEN 3 WHEN external_temperature < 30 THEN 4 WHEN external_temperature < 35 THEN 5 ELSE 6 END AS Bracket_Order,
        CASE WHEN external_temperature < 15 THEN '< 15C' WHEN external_temperature < 20 THEN '15C - 20C' WHEN external_temperature < 25 THEN '20C - 25C' WHEN external_temperature < 30 THEN '25C - 30C' WHEN external_temperature < 35 THEN '30C - 35C' ELSE '35C+' END AS Temperature_Bracket
    FROM dbo.ElectricityReadings
    WHERE external_temperature IS NOT NULL
)
SELECT Temperature_Bracket, COUNT(*) AS Reading_Count, ROUND(AVG(P_agg), 2) AS Avg_Total_Watts, ROUND(AVG(AC_Power), 2) AS Avg_AC_Watts
FROM TempBrackets
GROUP BY Bracket_Order, Temperature_Bracket
ORDER BY Bracket_Order;
GO

SELECT 
    household_id,
    CASE WHEN DATENAME(WEEKDAY, reading_time) IN ('Saturday', 'Sunday') THEN 'Weekend' ELSE 'Weekday' END AS Day_Type,
    COUNT(*) AS Reading_Count,
    ROUND(AVG(P_agg), 2) AS Avg_Power_Watts
FROM dbo.ElectricityReadings
GROUP BY household_id, CASE WHEN DATENAME(WEEKDAY, reading_time) IN ('Saturday', 'Sunday') THEN 'Weekend' ELSE 'Weekday' END
ORDER BY household_id, Day_Type;
GO
