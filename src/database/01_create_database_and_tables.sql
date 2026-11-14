IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'SmartEnergy_DB')
BEGIN
    CREATE DATABASE SmartEnergy_DB;
END
GO

USE SmartEnergy_DB;
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'staging')
BEGIN
    EXEC('CREATE SCHEMA staging;');
END
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dwh')
BEGIN
    EXEC('CREATE SCHEMA dwh;');
END
GO

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
GO

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
GO

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
GO

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
GO

IF OBJECT_ID('dwh.Fact_Energy_Readings', 'U') IS NOT NULL DROP TABLE dwh.Fact_Energy_Readings;
CREATE TABLE dwh.Fact_Energy_Readings (
    Reading_ID BIGINT IDENTITY(1,1) PRIMARY KEY,
    House_ID VARCHAR(20) NOT NULL FOREIGN KEY REFERENCES dwh.Dim_House(House_ID),
    Reading_Time DATETIME2(0) NOT NULL,
    Voltage FLOAT NULL,
    Current_A FLOAT NULL,
    Aggregate_Power FLOAT NULL,
    AC_1 FLOAT NULL,
    AC_2 FLOAT NULL,
    Boiler FLOAT NULL,
    Fridge FLOAT NULL,
    Washing_Machine FLOAT NULL,
    Internal_Temperature FLOAT NULL,
    Internal_Humidity FLOAT NULL,
    External_Temperature FLOAT NULL,
    External_Humidity FLOAT NULL,
    Issues_Score FLOAT NULL
);
GO

CREATE NONCLUSTERED INDEX IX_Fact_Energy_House_Time 
ON dwh.Fact_Energy_Readings(House_ID, Reading_Time)
INCLUDE (Aggregate_Power, External_Temperature, AC_1, AC_2, Fridge, Boiler);
GO

CREATE NONCLUSTERED INDEX IX_Fact_Energy_Time 
ON dwh.Fact_Energy_Readings(Reading_Time)
INCLUDE (Aggregate_Power, External_Temperature);
GO
