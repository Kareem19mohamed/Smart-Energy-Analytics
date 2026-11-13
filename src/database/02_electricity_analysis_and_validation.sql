-- ============================================================================
-- Project: Electricity Consumption Analysis & Prediction
-- Script: 02_electricity_analysis_and_validation.sql
-- Database: ElectricityDB
-- Stages Covered: Stage 6 (SQL Analysis) & Stage 7 (Data Validation)
-- ============================================================================

USE ElectricityDB;
GO

PRINT '================================================================';
PRINT '   STAGE 7: DATA VALIDATION CHECKS                             ';
PRINT '================================================================';
GO

-- ----------------------------------------------------------------------------
-- 20. التحقق من إجمالي عدد الصفوف (Total Records = 119,375)
-- ----------------------------------------------------------------------------
SELECT 
    COUNT(*) AS Total_Records_In_DB,
    119375 AS Expected_Records,
    CASE 
        WHEN COUNT(*) = 119375 THEN 'PASSED: Total row count matches CSV files exactly.'
        ELSE 'FAILED: Total row count mismatch!'
    END AS Validation_Status
FROM dbo.ElectricityReadings;
GO

-- ----------------------------------------------------------------------------
-- 21. التحقق من توزيع البيانات على البيوت الثلاثة
-- House_01: 42,432 | House_03: 42,861 | House_04: 34,082
-- ----------------------------------------------------------------------------
SELECT 
    household_id,
    COUNT(*) AS Actual_Count,
    CASE household_id
        WHEN 'House_01' THEN 42432
        WHEN 'House_03' THEN 42861
        WHEN 'House_04' THEN 34082
    END AS Expected_Count,
    CASE 
        WHEN household_id = 'House_01' AND COUNT(*) = 42432 THEN 'PASSED'
        WHEN household_id = 'House_03' AND COUNT(*) = 42861 THEN 'PASSED'
        WHEN household_id = 'House_04' AND COUNT(*) = 34082 THEN 'PASSED'
        ELSE 'FAILED'
    END AS Status
FROM dbo.ElectricityReadings
GROUP BY household_id
ORDER BY household_id;
GO

-- ----------------------------------------------------------------------------
-- 22. التحقق من عدم وجود تكرار (Duplicate Timestamp per House)
-- ----------------------------------------------------------------------------
WITH Duplicates AS (
    SELECT 
        household_id, 
        reading_time, 
        COUNT(*) AS Duplicate_Count
    FROM dbo.ElectricityReadings
    GROUP BY household_id, reading_time
    HAVING COUNT(*) > 1
)
SELECT 
    ISNULL(COUNT(*), 0) AS Total_Duplicates,
    CASE 
        WHEN COUNT(*) = 0 THEN 'PASSED: No duplicate records found.'
        ELSE 'FAILED: Duplicate timestamps detected!'
    END AS Duplicate_Check_Status
FROM Duplicates;
GO

-- ----------------------------------------------------------------------------
-- 23. التحقق من القيم المفقودة (NULL Values Breakdown)
-- ----------------------------------------------------------------------------
SELECT 
    household_id,
    COUNT(*) AS Total_Rows,
    SUM(CASE WHEN reading_time IS NULL THEN 1 ELSE 0 END) AS Null_Reading_Time,
    SUM(CASE WHEN P_agg IS NULL THEN 1 ELSE 0 END) AS Null_P_agg,
    SUM(CASE WHEN V IS NULL THEN 1 ELSE 0 END) AS Null_Voltage,
    SUM(CASE WHEN A IS NULL THEN 1 ELSE 0 END) AS Null_Current,
    SUM(CASE WHEN external_temperature IS NULL THEN 1 ELSE 0 END) AS Null_Ext_Temp,
    SUM(CASE WHEN internal_temperature IS NULL THEN 1 ELSE 0 END) AS Null_Int_Temp
FROM dbo.ElectricityReadings
GROUP BY household_id;
GO


PRINT '================================================================';
PRINT '   STAGE 6: SQL QUERIES & DATA ANALYSIS                        ';
PRINT '================================================================';
GO

-- ----------------------------------------------------------------------------
-- 17. تحليل استهلاك كل بيت: مين متوسط استهلاكه أعلى؟
-- ----------------------------------------------------------------------------
SELECT 
    r.household_id,
    h.source_file,
    COUNT(*) AS Total_Readings,
    ROUND(AVG(r.P_agg), 2) AS Avg_Power_Watts,
    ROUND(MAX(r.P_agg), 2) AS Max_Peak_Power_Watts,
    ROUND(MIN(r.P_agg), 2) AS Min_Base_Power_Watts,
    -- Calculation: (Watts * 0.25 hours) / 1000 = kWh
    ROUND(SUM(r.P_agg * 0.25 / 1000.0), 2) AS Total_Energy_kWh,
    DENSE_RANK() OVER (ORDER BY AVG(r.P_agg) DESC) AS Consumption_Rank
FROM dbo.ElectricityReadings r
JOIN dbo.Households h ON r.household_id = h.household_id
GROUP BY r.household_id, h.source_file
ORDER BY Total_Energy_kWh DESC;
GO

-- ----------------------------------------------------------------------------
-- 18. اكتشاف Peak Consumption: إمتى بيحصل أعلى استهلاك في اليوم؟
-- ----------------------------------------------------------------------------
SELECT 
    household_id,
    DATEPART(HOUR, reading_time) AS Hour_Of_Day,
    ROUND(AVG(P_agg), 2) AS Avg_Power_Watts,
    ROUND(AVG(ISNULL(ac_1,0) + ISNULL(ac_2,0)), 2) AS Avg_AC_Watts,
    ROUND(AVG(boiler), 2) AS Avg_Boiler_Watts,
    ROUND(AVG(fridge), 2) AS Avg_Fridge_Watts,
    ROUND(AVG(external_temperature), 1) AS Avg_Outdoor_Temp_C,
    DENSE_RANK() OVER (PARTITION BY household_id ORDER BY AVG(P_agg) DESC) AS Hourly_Peak_Rank
FROM dbo.ElectricityReadings
GROUP BY household_id, DATEPART(HOUR, reading_time)
ORDER BY household_id, Hourly_Peak_Rank;
GO

-- ----------------------------------------------------------------------------
-- 19. مقارنة استهلاك الأجهزة (AC, Boiler, Fridge, Washing Machine)
-- ----------------------------------------------------------------------------
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
