USE ElectricityDB;
GO

CREATE OR ALTER VIEW dbo.vw_Household_KPIs AS
SELECT 
    r.household_id,
    h.source_file,
    COUNT(*) AS Total_Readings,
    MIN(r.reading_time) AS Data_Start_Date,
    MAX(r.reading_time) AS Data_End_Date,
    DATEDIFF(DAY, MIN(r.reading_time), MAX(r.reading_time)) + 1 AS Total_Monitored_Days,
    ROUND(AVG(r.P_agg), 2) AS Avg_Power_Watts,
    ROUND(MAX(r.P_agg), 2) AS Max_Peak_Power_Watts,
    ROUND(SUM(r.P_agg * 0.25 / 1000.0), 2) AS Total_Energy_kWh,
    ROUND(AVG(r.external_temperature), 1) AS Avg_External_Temp_C,
    ROUND(AVG(r.internal_temperature), 1) AS Avg_Internal_Temp_C
FROM dbo.ElectricityReadings r
JOIN dbo.Households h ON r.household_id = h.household_id
GROUP BY r.household_id, h.source_file;
GO

CREATE OR ALTER VIEW dbo.vw_ML_Feature_Store AS
WITH OrderedReadings AS (
    SELECT 
        household_id,
        reading_time,
        V,
        A,
        P_agg,
        ac_1,
        ac_2,
        boiler,
        fridge,
        washing_machine,
        internal_temperature,
        internal_humidity,
        external_temperature,
        external_humidity,
        CASE 
            WHEN DATEDIFF(MINUTE, LAG(reading_time, 1) OVER (PARTITION BY household_id ORDER BY reading_time), reading_time) = 15
            THEN LAG(P_agg, 1) OVER (PARTITION BY household_id ORDER BY reading_time)
        END AS Lag_15m_Power,
        CASE 
            WHEN DATEDIFF(MINUTE, LAG(reading_time, 4) OVER (PARTITION BY household_id ORDER BY reading_time), reading_time) = 60
            THEN LAG(P_agg, 4) OVER (PARTITION BY household_id ORDER BY reading_time)
        END AS Lag_1h_Power,
        CASE 
            WHEN DATEDIFF(MINUTE, LAG(reading_time, 96) OVER (PARTITION BY household_id ORDER BY reading_time), reading_time) = 1440
            THEN LAG(P_agg, 96) OVER (PARTITION BY household_id ORDER BY reading_time)
        END AS Lag_24h_Power,
        CASE 
            WHEN DATEDIFF(MINUTE, LAG(reading_time, 3) OVER (PARTITION BY household_id ORDER BY reading_time), reading_time) = 45
            THEN AVG(P_agg) OVER (PARTITION BY household_id ORDER BY reading_time ROWS BETWEEN 3 PRECEDING AND CURRENT ROW)
        END AS Rolling_1h_Avg_Power,
        CASE 
            WHEN DATEDIFF(MINUTE, reading_time, LEAD(reading_time, 1) OVER (PARTITION BY household_id ORDER BY reading_time)) = 15
            THEN LEAD(P_agg, 1) OVER (PARTITION BY household_id ORDER BY reading_time)
        END AS Target_Next_15m_Power
    FROM dbo.ElectricityReadings
)
SELECT
    household_id,
    reading_time,
    DATEPART(YEAR, reading_time) AS Year,
    DATEPART(MONTH, reading_time) AS Month,
    DATEPART(DAY, reading_time) AS Day,
    DATEPART(HOUR, reading_time) AS Hour,
    DATEPART(MINUTE, reading_time) AS Minute,
    DATENAME(WEEKDAY, reading_time) AS Day_Name,
    CASE WHEN ((DATEPART(WEEKDAY, reading_time) + @@DATEFIRST) % 7) IN (0, 1) THEN 1 ELSE 0 END AS Is_Weekend,
    external_temperature,
    external_humidity,
    internal_temperature,
    internal_humidity,
    V,
    A,
    ac_1,
    ac_2,
    CASE WHEN ac_1 IS NULL AND ac_2 IS NULL THEN NULL ELSE ISNULL(ac_1, 0) + ISNULL(ac_2, 0) END AS Total_AC_Power,
    boiler,
    fridge,
    washing_machine,
    Lag_15m_Power,
    Lag_1h_Power,
    Lag_24h_Power,
    ROUND(Rolling_1h_Avg_Power, 2) AS Rolling_1h_Avg_Power,
    P_agg AS Current_Power_Watts,
    Target_Next_15m_Power
FROM OrderedReadings;
GO
