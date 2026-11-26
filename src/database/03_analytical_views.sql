USE ElectricityDB;
GO

CREATE OR ALTER VIEW dbo.vw_Household_KPIs AS
WITH StepCheck AS (
    SELECT 
        household_id,
        reading_time,
        P_agg,
        external_temperature,
        internal_temperature,
        CASE 
            WHEN LAG(reading_time) OVER (PARTITION BY household_id ORDER BY reading_time) IS NULL THEN 1
            WHEN DATEDIFF(MINUTE, LAG(reading_time) OVER (PARTITION BY household_id ORDER BY reading_time), reading_time) = 15 THEN 1
            ELSE 0
        END AS Is_Regular_15m
    FROM dbo.ElectricityReadings
)
SELECT 
    s.household_id,
    h.source_file,
    COUNT(*) AS Total_Readings,
    SUM(s.Is_Regular_15m) AS Regular_15m_Readings,
    MIN(s.reading_time) AS Data_Start_Date,
    MAX(s.reading_time) AS Data_End_Date,
    DATEDIFF(DAY, MIN(s.reading_time), MAX(s.reading_time)) + 1 AS Total_Monitored_Days,
    ROUND(AVG(s.P_agg), 2) AS Avg_Power_Watts,
    ROUND(MAX(s.P_agg), 2) AS Max_Peak_Power_Watts,
    ROUND(SUM(CASE WHEN s.Is_Regular_15m = 1 THEN s.P_agg * 0.25 / 1000.0 END), 2) AS Total_Energy_kWh,
    ROUND(AVG(s.external_temperature), 1) AS Avg_External_Temp_C,
    ROUND(AVG(s.internal_temperature), 1) AS Avg_Internal_Temp_C
FROM StepCheck s
JOIN dbo.Households h ON s.household_id = h.household_id
GROUP BY s.household_id, h.source_file;
GO

CREATE OR ALTER VIEW dbo.vw_ML_Feature_Store AS
WITH StepIntervals AS (
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
        DATEDIFF(MINUTE, LAG(reading_time, 1) OVER (PARTITION BY household_id ORDER BY reading_time), reading_time) AS Prev_Step_Min,
        DATEDIFF(MINUTE, reading_time, LEAD(reading_time, 1) OVER (PARTITION BY household_id ORDER BY reading_time)) AS Next_Step_Min,
        CASE 
            WHEN DATEDIFF(MINUTE, LAG(reading_time, 1) OVER (PARTITION BY household_id ORDER BY reading_time), reading_time) = 15 THEN 0
            ELSE 1
        END AS Is_Irregular_Step
    FROM dbo.ElectricityReadings
),
WindowChecked AS (
    SELECT 
        *,
        SUM(Is_Irregular_Step) OVER (
            PARTITION BY household_id 
            ORDER BY reading_time 
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS Irregular_Steps_Last_3,
        SUM(Is_Irregular_Step) OVER (
            PARTITION BY household_id 
            ORDER BY reading_time 
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
        ) AS Irregular_Steps_Last_4,
        SUM(Is_Irregular_Step) OVER (
            PARTITION BY household_id 
            ORDER BY reading_time 
            ROWS BETWEEN 95 PRECEDING AND CURRENT ROW
        ) AS Irregular_Steps_Last_96,
        LAG(P_agg, 1) OVER (PARTITION BY household_id ORDER BY reading_time) AS Raw_Lag_15m,
        LAG(P_agg, 4) OVER (PARTITION BY household_id ORDER BY reading_time) AS Raw_Lag_1h,
        LAG(P_agg, 96) OVER (PARTITION BY household_id ORDER BY reading_time) AS Raw_Lag_24h,
        AVG(P_agg) OVER (
            PARTITION BY household_id 
            ORDER BY reading_time 
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
        ) AS Raw_Rolling_1h_Avg,
        LEAD(P_agg, 1) OVER (PARTITION BY household_id ORDER BY reading_time) AS Raw_Lead_15m
    FROM StepIntervals
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
    CASE WHEN Prev_Step_Min = 15 THEN Raw_Lag_15m END AS Lag_15m_Power,
    CASE WHEN Irregular_Steps_Last_4 = 0 THEN Raw_Lag_1h END AS Lag_1h_Power,
    CASE WHEN Irregular_Steps_Last_96 = 0 THEN Raw_Lag_24h END AS Lag_24h_Power,
    CASE WHEN Irregular_Steps_Last_3 = 0 THEN ROUND(Raw_Rolling_1h_Avg, 2) END AS Rolling_1h_Avg_Power,
    P_agg AS Current_Power_Watts,
    CASE WHEN Next_Step_Min = 15 THEN Raw_Lead_15m END AS Target_Next_15m_Power
FROM WindowChecked;
GO
