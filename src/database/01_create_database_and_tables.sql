-- ============================================================================
-- Project: Smart Energy Analytics & Prediction
-- Script 01: Database, Schemas, Dimensions, and Fact Tables
-- Author: Data Engineering Team
-- Engine: Microsoft SQL Server (T-SQL)
-- ============================================================================

-- 1. Create Database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'SmartEnergy_DB')
BEGIN
    CREATE DATABASE SmartEnergy_DB;
    PRINT 'Database [SmartEnergy_DB] created successfully.';
END
GO

USE SmartEnergy_DB;
GO

-- 2. Create Schemas
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'staging')
BEGIN
    EXEC('CREATE SCHEMA staging;');
    PRINT 'Schema [staging] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dwh')
BEGIN
    EXEC('CREATE SCHEMA dwh;');
    PRINT 'Schema [dwh] created.';
END
GO

-- ============================================================================
-- 3. Staging Tables (To ingest raw CSV files with exact source columns)
-- ============================================================================

-- Staging for House 01 (Contains 15 columns: has both external_temparature and external_temperature)
IF OBJECT_ID('staging.House_01_Raw', 'U') IS NOT NULL DROP TABLE staging.House_01_Raw;
CREATE TABLE staging.House_01_Raw (
    timestamp VARCHAR(50),
    V VARCHAR(50),
    A VARCHAR(50),
    P_agg VARCHAR(50),
    ac_1 VARCHAR(50),
    ac_2 VARCHAR(50),
    boiler VARCHAR(50),
    fridge VARCHAR(50),
    washing_machine VARCHAR(50),
    issues VARCHAR(50),
    internal_temperature VARCHAR(50),
    internal_humidity VARCHAR(50),
    external_temparature VARCHAR(50),
    external_humidity VARCHAR(50),
    external_temperature VARCHAR(50)
);
PRINT 'Table [staging.House_01_Raw] created.';
GO

-- Staging for House 03 (14 columns)
IF OBJECT_ID('staging.House_03_Raw', 'U') IS NOT NULL DROP TABLE staging.House_03_Raw;
CREATE TABLE staging.House_03_Raw (
    timestamp VARCHAR(50),
    V VARCHAR(50),
    A VARCHAR(50),
    P_agg VARCHAR(50),
    ac_1 VARCHAR(50),
    ac_2 VARCHAR(50),
    boiler VARCHAR(50),
    fridge VARCHAR(50),
    washing_machine VARCHAR(50),
    issues VARCHAR(50),
    internal_temperature VARCHAR(50),
    internal_humidity VARCHAR(50),
    external_temperature VARCHAR(50),
    external_humidity VARCHAR(50)
);
PRINT 'Table [staging.House_03_Raw] created.';
GO

-- Staging for House 04 (14 columns)
IF OBJECT_ID('staging.House_04_Raw', 'U') IS NOT NULL DROP TABLE staging.House_04_Raw;
CREATE TABLE staging.House_04_Raw (
    timestamp VARCHAR(50),
    V VARCHAR(50),
    A VARCHAR(50),
    P_agg VARCHAR(50),
    ac_1 VARCHAR(50),
    ac_2 VARCHAR(50),
    boiler VARCHAR(50),
    fridge VARCHAR(50),
    washing_machine VARCHAR(50),
    issues VARCHAR(50),
    internal_temperature VARCHAR(50),
    internal_humidity VARCHAR(50),
    external_temperature VARCHAR(50),
    external_humidity VARCHAR(50)
);
PRINT 'Table [staging.House_04_Raw] created.';
GO

-- ============================================================================
-- 4. Analytical Data Warehouse Tables (DWH Layer)
-- ============================================================================

-- Dimension: Dim_House
IF OBJECT_ID('dwh.Dim_House', 'U') IS NOT NULL DROP TABLE dwh.Dim_House;
CREATE TABLE dwh.Dim_House (
    House_ID VARCHAR(20) PRIMARY KEY,
    House_Name NVARCHAR(100) NOT NULL,
    Description NVARCHAR(255) NULL,
    City NVARCHAR(100) DEFAULT 'Athens',
    Country NVARCHAR(100) DEFAULT 'Greece',
    Monitored_Appliances INT DEFAULT 5,
    Created_At DATETIME2 DEFAULT SYSDATETIME()
);
PRINT 'Table [dwh.Dim_House] created.';
GO

-- Fact Table: Fact_Energy_Readings
IF OBJECT_ID('dwh.Fact_Energy_Readings', 'U') IS NOT NULL DROP TABLE dwh.Fact_Energy_Readings;
CREATE TABLE dwh.Fact_Energy_Readings (
    Reading_ID BIGINT IDENTITY(1,1) PRIMARY KEY,
    House_ID VARCHAR(20) NOT NULL FOREIGN KEY REFERENCES dwh.Dim_House(House_ID),
    Reading_Time DATETIME2(0) NOT NULL,
    Voltage FLOAT NULL,
    Current_A FLOAT NULL,
    Aggregate_Power FLOAT NULL,          -- Total active power (Watts)
    AC_1 FLOAT NULL,                     -- AC Unit 1 power (Watts)
    AC_2 FLOAT NULL,                     -- AC Unit 2 power (Watts)
    Boiler FLOAT NULL,                   -- Water Boiler power (Watts)
    Fridge FLOAT NULL,                   -- Refrigerator power (Watts)
    Washing_Machine FLOAT NULL,          -- Washing machine power (Watts)
    Internal_Temperature FLOAT NULL,     -- Indoor temp (Celsius)
    Internal_Humidity FLOAT NULL,        -- Indoor relative humidity (%)
    External_Temperature FLOAT NULL,     -- Outdoor temp (Celsius)
    External_Humidity FLOAT NULL,        -- Outdoor relative humidity (%)
    Issues_Score FLOAT NULL              -- Injected quality issues metric
);
PRINT 'Table [dwh.Fact_Energy_Readings] created.';
GO

-- ============================================================================
-- 5. Performance Indexes (Crucial for Dashboard & ML speed)
-- ============================================================================

-- Index on House and Time (most frequent filter)
CREATE NONCLUSTERED INDEX IX_Fact_Energy_House_Time 
ON dwh.Fact_Energy_Readings(House_ID, Reading_Time)
INCLUDE (Aggregate_Power, External_Temperature, AC_1, AC_2, Fridge, Boiler);
PRINT 'Index [IX_Fact_Energy_House_Time] created.';
GO

-- Index on Reading_Time alone for cross-house temporal aggregations
CREATE NONCLUSTERED INDEX IX_Fact_Energy_Time 
ON dwh.Fact_Energy_Readings(Reading_Time)
INCLUDE (Aggregate_Power, External_Temperature);
PRINT 'Index [IX_Fact_Energy_Time] created.';
GO
