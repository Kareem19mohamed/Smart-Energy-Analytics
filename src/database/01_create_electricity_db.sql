-- ============================================================================
-- Project: Electricity Consumption Analysis & Prediction
-- Part 3: Database & SQL
-- Database: ElectricityDB
-- Target Schema: Households (Parent) & ElectricityReadings (Child)
-- ============================================================================

-- 1. Create Database: ElectricityDB
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'ElectricityDB')
BEGIN
    CREATE DATABASE ElectricityDB;
    PRINT 'Database [ElectricityDB] created successfully.';
END
GO

USE ElectricityDB;
GO

-- 2. Drop existing tables if needed (drop child first, then parent)
IF OBJECT_ID('dbo.ElectricityReadings', 'U') IS NOT NULL DROP TABLE dbo.ElectricityReadings;
IF OBJECT_ID('dbo.Households', 'U') IS NOT NULL DROP TABLE dbo.Households;
GO

-- 3. Create Parent Table: Households
CREATE TABLE dbo.Households (
    household_id VARCHAR(20) NOT NULL,
    source_file VARCHAR(100) NOT NULL,
    description NVARCHAR(255) NULL,
    created_at DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Households PRIMARY KEY (household_id)
);
PRINT 'Table [Households] created with Primary Key (household_id).';
GO

-- 4. Create Child Table: ElectricityReadings
-- Uses Composite Primary Key: (household_id, reading_time)
CREATE TABLE dbo.ElectricityReadings (
    household_id VARCHAR(20) NOT NULL,
    reading_time DATETIME2(0) NOT NULL,
    V FLOAT NULL,
    A FLOAT NULL,
    P_agg FLOAT NULL,
    ac_1 FLOAT NULL,
    ac_2 FLOAT NULL,
    boiler FLOAT NULL,
    fridge FLOAT NULL,
    washing_machine FLOAT NULL,
    issues FLOAT NULL,
    internal_temperature FLOAT NULL,
    internal_humidity FLOAT NULL,
    external_temperature FLOAT NULL,
    external_humidity FLOAT NULL,
    
    -- Composite Primary Key: Ensures a single house cannot have duplicate readings at the exact same timestamp
    CONSTRAINT PK_ElectricityReadings PRIMARY KEY (household_id, reading_time),
    
    -- Foreign Key: Links each reading to a registered household
    CONSTRAINT FK_Readings_Households FOREIGN KEY (household_id) 
        REFERENCES dbo.Households(household_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
PRINT 'Table [ElectricityReadings] created with Composite PK and Foreign Key.';
GO

-- 5. Helpful Performance Indexes
CREATE NONCLUSTERED INDEX IX_Readings_Time ON dbo.ElectricityReadings(reading_time);
CREATE NONCLUSTERED INDEX IX_Readings_House_AggPower ON dbo.ElectricityReadings(household_id, P_agg);
PRINT 'Performance indexes created successfully.';
GO
