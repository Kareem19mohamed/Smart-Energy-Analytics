-- ============================================================================
-- Project: Smart Energy Analytics & Prediction
-- Script 05: Business & Analytics Queries (Answers to Core Project Questions)
-- Engine: Microsoft SQL Server (T-SQL)
-- ============================================================================

USE SmartEnergy_DB;
GO

-- ============================================================================
-- Question 1: متوسط استهلاك كل بيت وأي بيت استهلاكه أعلى؟
-- (Average consumption per house & which house consumes the most?)
-- ============================================================================
PRINT '>>> Question 1: House Consumption Ranking & Averages <<<';

SELECT 
    RANK() OVER (ORDER BY SUM(f.Aggregate_Power * 0.25 / 1000.0) DESC) AS Consumption_Rank,
    f.House_ID,
    h.House_Name,
    ROUND(AVG(f.Aggregate_Power), 2) AS Avg_Power_Watts,
    ROUND(MAX(f.Aggregate_Power), 2) AS Max_Peak_Power_Watts,
    ROUND(SUM(f.Aggregate_Power * 0.25 / 1000.0), 2) AS Total_Energy_kWh,
    -- Daily average kWh
    ROUND(SUM(f.Aggregate_Power * 0.25 / 1000.0) / (DATEDIFF(DAY, MIN(f.Reading_Time), MAX(f.Reading_Time)) + 1), 2) AS Avg_Daily_kWh,
    -- Estimated electricity cost (assuming 0.20 EUR per kWh)
    ROUND(SUM(f.Aggregate_Power * 0.25 / 1000.0) * 0.20, 2) AS Est_Total_Cost_EUR
FROM dwh.Fact_Energy_Readings f
JOIN dwh.Dim_House h ON f.House_ID = h.House_ID
GROUP BY f.House_ID, h.House_Name
ORDER BY Total_Energy_kWh DESC;
GO

-- ============================================================================
-- Question 2: إمتى بيحصل أعلى استهلاك في اليوم وليه؟
-- (When does peak consumption occur during the day and why?)
-- ============================================================================
PRINT '>>> Question 2: Peak Consumption Hours & Contributing Appliances <<<';

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
        WHEN Avg_AC_Power > Avg_Boiler_Power AND Avg_AC_Power > Avg_Fridge_Power THEN 'AC Driven (Cooling load)'
        WHEN Avg_Boiler_Power > Avg_AC_Power THEN 'Water Boiler Driven'
        ELSE 'General Appliance Activity'
    END AS Primary_Peak_Driver
FROM RankedHours
WHERE Peak_Rank <= 3
ORDER BY House_ID, Peak_Rank;
GO

-- ============================================================================
-- Question 3: ما هي الأجهزة الأكثر مساهمة في الاستهلاك في كل بيت؟
-- (Which appliances contribute the most to energy consumption?)
-- ============================================================================
PRINT '>>> Question 3: Appliance Contribution Ranking per House <<<';

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

-- ============================================================================
-- Question 4: هل الاستهلاك بيزيد مع ارتفاع درجة الحرارة الخارجية؟
-- (Does power consumption increase with rising outdoor temperature?)
-- ============================================================================
PRINT '>>> Question 4: Impact of Outdoor Temperature on Power & AC Usage <<<';

SELECT 
    Temperature_Bracket,
    COUNT(*) AS Total_Observations,
    ROUND(AVG(Avg_Total_Power_Watts), 2) AS Overall_Avg_Power_Watts,
    ROUND(AVG(Avg_AC_Power_Watts), 2) AS Overall_Avg_AC_Watts,
    -- AC percentage of total power during this temperature bracket
    ROUND((AVG(Avg_AC_Power_Watts) / NULLIF(AVG(Avg_Total_Power_Watts),0)) * 100, 2) AS AC_Pct_Of_Total
FROM dwh.vw_Temperature_vs_Power
GROUP BY Temperature_Bracket
ORDER BY Temperature_Bracket;
GO

-- ============================================================================
-- Question 5: مقارنة سلوك الاستهلاك بين عطلة نهاية الأسبوع وأيام العمل
-- (Weekday vs Weekend consumption patterns)
-- ============================================================================
PRINT '>>> Question 5: Weekend vs Weekday Consumption Behavior <<<';

SELECT 
    House_ID,
    CASE WHEN DATEPART(WEEKDAY, Reading_Time) IN (1, 7) THEN 'Weekend (Sat/Sun)' ELSE 'Weekday (Mon-Fri)' END AS Day_Type,
    COUNT(*) AS Reading_Count,
    ROUND(AVG(Aggregate_Power), 2) AS Avg_Power_Watts,
    ROUND(AVG(ISNULL(AC_1,0) + ISNULL(AC_2,0)), 2) AS Avg_AC_Watts,
    ROUND(AVG(Boiler), 2) AS Avg_Boiler_Watts,
    ROUND(AVG(Washing_Machine), 2) AS Avg_Washing_Machine_Watts
FROM dwh.Fact_Energy_Readings
GROUP BY 
    House_ID,
    CASE WHEN DATEPART(WEEKDAY, Reading_Time) IN (1, 7) THEN 'Weekend (Sat/Sun)' ELSE 'Weekday (Mon-Fri)' END
ORDER BY House_ID, Day_Type;
GO
