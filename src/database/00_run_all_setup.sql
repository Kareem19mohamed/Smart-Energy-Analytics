-- ============================================================================
-- Project: Smart Energy Analytics & Prediction
-- Script 00: MASTER EXECUTION SCRIPT
-- Description: Executes the complete end-to-end setup in sequential order.
-- ============================================================================

PRINT '================================================================';
PRINT '   STARTING FULL SMART ENERGY DATA WAREHOUSE PIPELINE           ';
PRINT '================================================================';
GO

-- Step 1: Create Database, Schemas, Dimensions, Facts, and Indexes
:r "C:\بروجيكت سيكول\01_create_database_and_tables.sql"
GO

-- Step 2: Populate Dimensions, Ingest CSVs into Staging, Transform into Fact Table
:r "C:\بروجيكت سيكول\02_load_data.sql"
GO

-- Step 3: Run Data Quality and Integrity Checks
:r "C:\بروجيكت سيكول\03_data_quality_checks.sql"
GO

-- Step 4: Build Analytical Views and ML Feature Store
:r "C:\بروجيكت سيكول\04_analytical_views_and_marts.sql"
GO

-- Step 5: Execute Core Business Questions
:r "C:\بروجيكت سيكول\05_business_queries_answers.sql"
GO

PRINT '================================================================';
PRINT '   SUCCESS! FULL PIPELINE EXECUTED SUCCESSFULLY                ';
PRINT '================================================================';
GO
