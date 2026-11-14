USE SmartEnergy_DB;
GO

SELECT 
    RANK() OVER (ORDER BY SUM(f.Aggregate_Power * 0.25 / 1000.0) DESC) AS Consumption_Rank,
    f.House_ID,
    h.House_Name,
    ROUND(AVG(f.Aggregate_Power), 2) AS Avg_Power_Watts,
    ROUND(MAX(f.Aggregate_Power), 2) AS Max_Peak_Power_Watts,
    ROUND(SUM(f.Aggregate_Power * 0.25 / 1000.0), 2) AS Total_Energy_kWh,
    ROUND(SUM(f.Aggregate_Power * 0.25 / 1000.0) / (DATEDIFF(DAY, MIN(f.Reading_Time), MAX(f.Reading_Time)) + 1), 2) AS Avg_Daily_kWh,
    ROUND(SUM(f.Aggregate_Power * 0.25 / 1000.0) * 0.20, 2) AS Est_Total_Cost_EUR
FROM dwh.Fact_Energy_Readings f
JOIN dwh.Dim_House h ON f.House_ID = h.House_ID
GROUP BY f.House_ID, h.House_Name
ORDER BY Total_Energy_kWh DESC;
GO

WITH HourlyBreakdown AS (
    SELECT 
        House_ID,
        DATEPART(HOUR, Reading_Time) AS Hour_Of_Day,
        ROUND(AVG(Aggregate_Power), 2) AS Avg_Total_Power,
        ROUND(AVG(ISNULL(AC_1,0) + ISNULL(AC_2,0)), 2) AS Avg_AC_Power,
        ROUND(AVG(Boiler), 2) AS Avg_Boiler_Power,
        ROUND(AVG(Fridge), 2) AS Avg_Fridge_Power,
        ROUND(AVG(Washing_Machine), 2) AS Avg_Washing_Machine_Power,
        ROUND(AVG(External_Temperature), 1) AS Avg_Temp
    FROM dwh.Fact_Energy_Readings
    GROUP BY House_ID, DATEPART(HOUR, Reading_Time)
),
RankedHours AS (
    SELECT *,
        DENSE_RANK() OVER (PARTITION BY House_ID ORDER BY Avg_Total_Power DESC) AS Peak_Rank
    FROM HourlyBreakdown
)
SELECT 
    House_ID,
    Peak_Rank,
    FORMAT(Hour_Of_Day, '00') + ':00' AS Time_Window,
    Avg_Total_Power AS Total_Watts,
    Avg_AC_Power AS AC_Watts,
    Avg_Boiler_Power AS Boiler_Watts,
    Avg_Fridge_Power AS Fridge_Watts,
    Avg_Washing_Machine_Power AS Washing_Watts,
    Avg_Temp AS Outdoor_Temp_C,
    CASE 
        WHEN Avg_AC_Power > Avg_Boiler_Power AND Avg_AC_Power > Avg_Fridge_Power THEN 'AC Driven'
        WHEN Avg_Boiler_Power > Avg_AC_Power THEN 'Water Boiler Driven'
        ELSE 'General Appliance Activity'
    END AS Primary_Peak_Driver
FROM RankedHours
WHERE Peak_Rank <= 3
ORDER BY House_ID, Peak_Rank;
GO

SELECT 
    House_ID,
    Total_Consumption_kWh,
    AC_kWh,
    AC_Share_Pct,
    Boiler_kWh,
    Boiler_Share_Pct,
    Fridge_kWh,
    Fridge_Share_Pct,
    WashingMachine_kWh,
    WashingMachine_Share_Pct,
    Other_Base_Load_kWh,
    Other_Base_Load_Pct
FROM dwh.vw_Appliance_Breakdown
ORDER BY House_ID;
GO

SELECT 
    Temperature_Bracket,
    COUNT(*) AS Total_Observations,
    ROUND(AVG(Avg_Total_Power_Watts), 2) AS Overall_Avg_Power_Watts,
    ROUND(AVG(Avg_AC_Power_Watts), 2) AS Overall_Avg_AC_Watts,
    ROUND((AVG(Avg_AC_Power_Watts) / NULLIF(AVG(Avg_Total_Power_Watts),0)) * 100, 2) AS AC_Pct_Of_Total
FROM dwh.vw_Temperature_vs_Power
GROUP BY Temperature_Bracket
ORDER BY Temperature_Bracket;
GO

SELECT 
    House_ID,
    CASE WHEN DATEPART(WEEKDAY, Reading_Time) IN (1, 7) THEN 'Weekend' ELSE 'Weekday' END AS Day_Type,
    COUNT(*) AS Reading_Count,
    ROUND(AVG(Aggregate_Power), 2) AS Avg_Power_Watts,
    ROUND(AVG(ISNULL(AC_1,0) + ISNULL(AC_2,0)), 2) AS Avg_AC_Watts,
    ROUND(AVG(Boiler), 2) AS Avg_Boiler_Watts,
    ROUND(AVG(Washing_Machine), 2) AS Avg_Washing_Machine_Watts
FROM dwh.Fact_Energy_Readings
GROUP BY 
    House_ID,
    CASE WHEN DATEPART(WEEKDAY, Reading_Time) IN (1, 7) THEN 'Weekend' ELSE 'Weekday' END
ORDER BY House_ID, Day_Type;
GO
