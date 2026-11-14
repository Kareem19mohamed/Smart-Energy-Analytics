USE SmartEnergy_DB;
GO

IF OBJECT_ID('dwh.vw_House_KPIs', 'V') IS NOT NULL DROP VIEW dwh.vw_House_KPIs;
GO
CREATE VIEW dwh.vw_House_KPIs AS
SELECT 
    f.House_ID,
    h.House_Name,
    COUNT(*) AS Total_Readings,
    MIN(f.Reading_Time) AS Data_Start_Date,
    MAX(f.Reading_Time) AS Data_End_Date,
    DATEDIFF(DAY, MIN(f.Reading_Time), MAX(f.Reading_Time)) + 1 AS Total_Monitored_Days,
    ROUND(AVG(f.Aggregate_Power), 2) AS Avg_Power_Watts,
    ROUND(MAX(f.Aggregate_Power), 2) AS Max_Peak_Power_Watts,
    ROUND(SUM(f.Aggregate_Power * 0.25 / 1000.0), 2) AS Total_Energy_kWh,
    ROUND(AVG(f.External_Temperature), 1) AS Avg_External_Temp_C,
    ROUND(AVG(f.Internal_Temperature), 1) AS Avg_Internal_Temp_C
FROM dwh.Fact_Energy_Readings f
JOIN dwh.Dim_House h ON f.House_ID = h.House_ID
GROUP BY f.House_ID, h.House_Name;
GO

IF OBJECT_ID('dwh.vw_Hourly_Peak_Analysis', 'V') IS NOT NULL DROP VIEW dwh.vw_Hourly_Peak_Analysis;
GO
CREATE VIEW dwh.vw_Hourly_Peak_Analysis AS
SELECT 
    House_ID,
    DATEPART(HOUR, Reading_Time) AS Hour_Of_Day,
    ROUND(AVG(Aggregate_Power), 2) AS Avg_Total_Power_Watts,
    ROUND(AVG(ISNULL(AC_1,0) + ISNULL(AC_2,0)), 2) AS Avg_AC_Power_Watts,
    ROUND(AVG(Boiler), 2) AS Avg_Boiler_Power_Watts,
    ROUND(AVG(Fridge), 2) AS Avg_Fridge_Power_Watts,
    ROUND(AVG(Washing_Machine), 2) AS Avg_Washing_Machine_Power_Watts,
    ROUND(AVG(External_Temperature), 2) AS Avg_Outdoor_Temp_C,
    CASE 
        WHEN DATEPART(HOUR, Reading_Time) BETWEEN 12 AND 17 THEN 'Afternoon Peak'
        WHEN DATEPART(HOUR, Reading_Time) BETWEEN 18 AND 23 THEN 'Evening Peak'
        WHEN DATEPART(HOUR, Reading_Time) BETWEEN 0 AND 5 THEN 'Night Off-Peak'
        ELSE 'Morning Transition'
    END AS Day_Period
FROM dwh.Fact_Energy_Readings
GROUP BY House_ID, DATEPART(HOUR, Reading_Time);
GO

IF OBJECT_ID('dwh.vw_Appliance_Breakdown', 'V') IS NOT NULL DROP VIEW dwh.vw_Appliance_Breakdown;
GO
CREATE VIEW dwh.vw_Appliance_Breakdown AS
WITH TotalEnergy AS (
    SELECT 
        House_ID,
        SUM(Aggregate_Power * 0.25 / 1000.0) AS Total_kWh,
        SUM((ISNULL(AC_1,0) + ISNULL(AC_2,0)) * 0.25 / 1000.0) AS Total_AC_kWh,
        SUM(ISNULL(Boiler,0) * 0.25 / 1000.0) AS Total_Boiler_kWh,
        SUM(ISNULL(Fridge,0) * 0.25 / 1000.0) AS Total_Fridge_kWh,
        SUM(ISNULL(Washing_Machine,0) * 0.25 / 1000.0) AS Total_WashingMachine_kWh
    FROM dwh.Fact_Energy_Readings
    GROUP BY House_ID
)
SELECT 
    House_ID,
    ROUND(Total_kWh, 2) AS Total_Consumption_kWh,
    ROUND(Total_AC_kWh, 2) AS AC_kWh,
    ROUND((Total_AC_kWh / NULLIF(Total_kWh,0)) * 100, 2) AS AC_Share_Pct,
    ROUND(Total_Boiler_kWh, 2) AS Boiler_kWh,
    ROUND((Total_Boiler_kWh / NULLIF(Total_kWh,0)) * 100, 2) AS Boiler_Share_Pct,
    ROUND(Total_Fridge_kWh, 2) AS Fridge_kWh,
    ROUND((Total_Fridge_kWh / NULLIF(Total_kWh,0)) * 100, 2) AS Fridge_Share_Pct,
    ROUND(Total_WashingMachine_kWh, 2) AS WashingMachine_kWh,
    ROUND((Total_WashingMachine_kWh / NULLIF(Total_kWh,0)) * 100, 2) AS WashingMachine_Share_Pct,
    ROUND(Total_kWh - (Total_AC_kWh + Total_Boiler_kWh + Total_Fridge_kWh + Total_WashingMachine_kWh), 2) AS Other_Base_Load_kWh,
    ROUND(((Total_kWh - (Total_AC_kWh + Total_Boiler_kWh + Total_Fridge_kWh + Total_WashingMachine_kWh)) / NULLIF(Total_kWh,0)) * 100, 2) AS Other_Base_Load_Pct
FROM TotalEnergy;
GO

IF OBJECT_ID('dwh.vw_Temperature_vs_Power', 'V') IS NOT NULL DROP VIEW dwh.vw_Temperature_vs_Power;
GO
CREATE VIEW dwh.vw_Temperature_vs_Power AS
SELECT 
    House_ID,
    CASE 
        WHEN External_Temperature < 15 THEN '< 15C'
        WHEN External_Temperature BETWEEN 15 AND 20 THEN '15C - 20C'
        WHEN External_Temperature BETWEEN 20.01 AND 25 THEN '20C - 25C'
        WHEN External_Temperature BETWEEN 25.01 AND 30 THEN '25C - 30C'
        WHEN External_Temperature BETWEEN 30.01 AND 35 THEN '30C - 35C'
        ELSE '> 35C'
    END AS Temperature_Bracket,
    COUNT(*) AS Reading_Count,
    ROUND(AVG(Aggregate_Power), 2) AS Avg_Total_Power_Watts,
    ROUND(AVG(ISNULL(AC_1,0) + ISNULL(AC_2,0)), 2) AS Avg_AC_Power_Watts,
    ROUND(AVG(External_Temperature), 1) AS Avg_Temp_In_Bracket
FROM dwh.Fact_Energy_Readings
WHERE External_Temperature IS NOT NULL
GROUP BY 
    House_ID,
    CASE 
        WHEN External_Temperature < 15 THEN '< 15C'
        WHEN External_Temperature BETWEEN 15 AND 20 THEN '15C - 20C'
        WHEN External_Temperature BETWEEN 20.01 AND 25 THEN '20C - 25C'
        WHEN External_Temperature BETWEEN 25.01 AND 30 THEN '25C - 30C'
        WHEN External_Temperature BETWEEN 30.01 AND 35 THEN '30C - 35C'
        ELSE '> 35C'
    END;
GO

IF OBJECT_ID('dwh.vw_ML_Feature_Store', 'V') IS NOT NULL DROP VIEW dwh.vw_ML_Feature_Store;
GO
CREATE VIEW dwh.vw_ML_Feature_Store AS
WITH OrderedReadings AS (
    SELECT 
        Reading_ID,
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
        LAG(Aggregate_Power, 1) OVER (PARTITION BY House_ID ORDER BY Reading_Time) AS Lag_15m_Power,
        LAG(Aggregate_Power, 4) OVER (PARTITION BY House_ID ORDER BY Reading_Time) AS Lag_1h_Power,
        LAG(Aggregate_Power, 96) OVER (PARTITION BY House_ID ORDER BY Reading_Time) AS Lag_24h_Power,
        AVG(Aggregate_Power) OVER (
            PARTITION BY House_ID 
            ORDER BY Reading_Time 
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
        ) AS Rolling_1h_Avg_Power,
        LEAD(Aggregate_Power, 1) OVER (PARTITION BY House_ID ORDER BY Reading_Time) AS Target_Next_15m_Power
    FROM dwh.Fact_Energy_Readings
)
SELECT 
    Reading_ID,
    House_ID,
    Reading_Time,
    DATEPART(YEAR, Reading_Time) AS Year,
    DATEPART(MONTH, Reading_Time) AS Month,
    DATEPART(DAY, Reading_Time) AS Day,
    DATEPART(HOUR, Reading_Time) AS Hour,
    DATEPART(MINUTE, Reading_Time) AS Minute,
    DATEPART(WEEKDAY, Reading_Time) AS Day_Of_Week,
    DATENAME(WEEKDAY, Reading_Time) AS Day_Name,
    CASE WHEN DATEPART(WEEKDAY, Reading_Time) IN (1, 7) THEN 1 ELSE 0 END AS Is_Weekend,
    External_Temperature,
    External_Humidity,
    Internal_Temperature,
    Internal_Humidity,
    Voltage,
    Current_A,
    ISNULL(AC_1,0) + ISNULL(AC_2,0) AS Total_AC_Power,
    Boiler,
    Fridge,
    Washing_Machine,
    Lag_15m_Power,
    Lag_1h_Power,
    Lag_24h_Power,
    ROUND(Rolling_1h_Avg_Power, 2) AS Rolling_1h_Avg_Power,
    Aggregate_Power AS Current_Power_Watts,
    Target_Next_15m_Power
FROM OrderedReadings;
GO
