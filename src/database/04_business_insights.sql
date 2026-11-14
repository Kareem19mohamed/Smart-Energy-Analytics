USE ElectricityDB;
GO

SELECT 
    r.household_id,
    h.source_file,
    COUNT(*) AS Total_Readings,
    ROUND(AVG(r.P_agg), 2) AS Avg_Power_Watts,
    ROUND(MAX(r.P_agg), 2) AS Max_Peak_Power_Watts,
    ROUND(MIN(r.P_agg), 2) AS Min_Base_Power_Watts,
    ROUND(SUM(r.P_agg * 0.25 / 1000.0), 2) AS Total_Energy_kWh,
    DENSE_RANK() OVER (ORDER BY AVG(r.P_agg) DESC) AS Consumption_Rank
FROM dbo.ElectricityReadings r
JOIN dbo.Households h ON r.household_id = h.household_id
GROUP BY r.household_id, h.source_file
ORDER BY Total_Energy_kWh DESC;
GO

WITH HourlyBreakdown AS (
    SELECT 
        household_id,
        DATEPART(HOUR, reading_time) AS Hour_Of_Day,
        ROUND(AVG(P_agg), 2) AS Avg_Power_Watts,
        ROUND(AVG(ISNULL(ac_1,0) + ISNULL(ac_2,0)), 2) AS Avg_AC_Watts,
        ROUND(AVG(boiler), 2) AS Avg_Boiler_Watts,
        ROUND(AVG(fridge), 2) AS Avg_Fridge_Watts,
        ROUND(AVG(washing_machine), 2) AS Avg_Washing_Watts,
        ROUND(AVG(external_temperature), 1) AS Avg_Outdoor_Temp_C
    FROM dbo.ElectricityReadings
    GROUP BY household_id, DATEPART(HOUR, reading_time)
),
RankedHours AS (
    SELECT *,
        DENSE_RANK() OVER (PARTITION BY household_id ORDER BY Avg_Power_Watts DESC) AS Peak_Rank
    FROM HourlyBreakdown
)
SELECT 
    household_id,
    Peak_Rank,
    FORMAT(Hour_Of_Day, '00') + ':00' AS Time_Window,
    Avg_Power_Watts AS Total_Watts,
    Avg_AC_Watts AS AC_Watts,
    Avg_Boiler_Watts AS Boiler_Watts,
    Avg_Fridge_Watts AS Fridge_Watts,
    Avg_Washing_Watts AS Washing_Watts,
    Avg_Outdoor_Temp_C AS Outdoor_Temp_C,
    CASE 
        WHEN Avg_AC_Watts > Avg_Boiler_Watts AND Avg_AC_Watts > Avg_Fridge_Watts THEN 'AC Driven'
        WHEN Avg_Boiler_Watts > Avg_AC_Watts THEN 'Water Boiler Driven'
        ELSE 'General Appliance Activity'
    END AS Primary_Peak_Driver
FROM RankedHours
WHERE Peak_Rank <= 3
ORDER BY household_id, Peak_Rank;
GO

SELECT 
    household_id,
    ROUND(SUM(P_agg * 0.25 / 1000.0), 2) AS Total_kWh,
    ROUND(SUM((ISNULL(ac_1,0) + ISNULL(ac_2,0)) * 0.25 / 1000.0), 2) AS Total_AC_kWh,
    ROUND((SUM((ISNULL(ac_1,0) + ISNULL(ac_2,0)) * 0.25 / 1000.0) / NULLIF(SUM(P_agg * 0.25 / 1000.0),0)) * 100, 2) AS AC_Share_Pct,
    ROUND(SUM(ISNULL(boiler,0) * 0.25 / 1000.0), 2) AS Total_Boiler_kWh,
    ROUND((SUM(ISNULL(boiler,0) * 0.25 / 1000.0) / NULLIF(SUM(P_agg * 0.25 / 1000.0),0)) * 100, 2) AS Boiler_Share_Pct,
    ROUND(SUM(ISNULL(fridge,0) * 0.25 / 1000.0), 2) AS Total_Fridge_kWh,
    ROUND((SUM(ISNULL(fridge,0) * 0.25 / 1000.0) / NULLIF(SUM(P_agg * 0.25 / 1000.0),0)) * 100, 2) AS Fridge_Share_Pct,
    ROUND(SUM(ISNULL(washing_machine,0) * 0.25 / 1000.0), 2) AS Total_WashingMachine_kWh,
    ROUND((SUM(ISNULL(washing_machine,0) * 0.25 / 1000.0) / NULLIF(SUM(P_agg * 0.25 / 1000.0),0)) * 100, 2) AS WashingMachine_Share_Pct
FROM dbo.ElectricityReadings
GROUP BY household_id
ORDER BY household_id;
GO

SELECT 
    CASE 
        WHEN external_temperature < 15 THEN '< 15C'
        WHEN external_temperature BETWEEN 15 AND 20 THEN '15C - 20C'
        WHEN external_temperature BETWEEN 20.01 AND 25 THEN '20C - 25C'
        WHEN external_temperature BETWEEN 25.01 AND 30 THEN '25C - 30C'
        WHEN external_temperature BETWEEN 30.01 AND 35 THEN '30C - 35C'
        ELSE '> 35C'
    END AS Temperature_Bracket,
    COUNT(*) AS Reading_Count,
    ROUND(AVG(P_agg), 2) AS Avg_Total_Power_Watts,
    ROUND(AVG(ISNULL(ac_1,0) + ISNULL(ac_2,0)), 2) AS Avg_AC_Power_Watts,
    ROUND((AVG(ISNULL(ac_1,0) + ISNULL(ac_2,0)) / NULLIF(AVG(P_agg),0)) * 100, 2) AS AC_Pct_Of_Total
FROM dbo.ElectricityReadings
WHERE external_temperature IS NOT NULL
GROUP BY 
    CASE 
        WHEN external_temperature < 15 THEN '< 15C'
        WHEN external_temperature BETWEEN 15 AND 20 THEN '15C - 20C'
        WHEN external_temperature BETWEEN 20.01 AND 25 THEN '20C - 25C'
        WHEN external_temperature BETWEEN 25.01 AND 30 THEN '25C - 30C'
        WHEN external_temperature BETWEEN 30.01 AND 35 THEN '30C - 35C'
        ELSE '> 35C'
    END
ORDER BY Temperature_Bracket;
GO

SELECT 
    household_id,
    CASE WHEN DATEPART(WEEKDAY, reading_time) IN (1, 7) THEN 'Weekend' ELSE 'Weekday' END AS Day_Type,
    COUNT(*) AS Reading_Count,
    ROUND(AVG(P_agg), 2) AS Avg_Power_Watts,
    ROUND(AVG(ISNULL(ac_1,0) + ISNULL(ac_2,0)), 2) AS Avg_AC_Watts,
    ROUND(AVG(boiler), 2) AS Avg_Boiler_Watts,
    ROUND(AVG(washing_machine), 2) AS Avg_Washing_Machine_Watts
FROM dbo.ElectricityReadings
GROUP BY 
    household_id,
    CASE WHEN DATEPART(WEEKDAY, reading_time) IN (1, 7) THEN 'Weekend' ELSE 'Weekday' END
ORDER BY household_id, Day_Type;
GO
