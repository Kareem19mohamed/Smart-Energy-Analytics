IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'ElectricityDB')
BEGIN
    CREATE DATABASE ElectricityDB;
END
GO

USE ElectricityDB;
GO

IF OBJECT_ID('dbo.Households', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Households (
        household_id VARCHAR(20) NOT NULL,
        source_file VARCHAR(100) NOT NULL,
        description NVARCHAR(255) NULL,
        created_at DATETIME2 DEFAULT SYSDATETIME(),
        CONSTRAINT PK_Households PRIMARY KEY (household_id)
    );
END
GO

IF OBJECT_ID('dbo.ElectricityReadings', 'U') IS NULL
BEGIN
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
        CONSTRAINT PK_ElectricityReadings PRIMARY KEY (household_id, reading_time),
        CONSTRAINT FK_Readings_Households FOREIGN KEY (household_id) REFERENCES dbo.Households(household_id)
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_Readings_Time' AND object_id = OBJECT_ID('dbo.ElectricityReadings')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Readings_Time
    ON dbo.ElectricityReadings(reading_time);
END
GO
