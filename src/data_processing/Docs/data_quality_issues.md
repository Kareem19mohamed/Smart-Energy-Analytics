# Data Quality Issues Injection

## Overview
This module introduces synthetic data quality issues into the processed smart meter datasets to simulate real-world data problems.

## Supported Issue Types

1. **Missing Values:** Replaces selected valid sensor readings with NaN.
2. **Outliers:** Injects extreme values into selected sensor columns.
3. **Stuck Sensor Readings:** Repeats the same sensor value across six consecutive readings.
4. **Duplicate Records:** Appends exact duplicate rows to the dataset.

## Input
The script reads the original processed datasets from:

`data/processed/`

Supported datasets:
- House_01.csv
- House_03.csv
- House_04.csv

## Output
Generated datasets are saved in:

`data/quality_issues/`

The issue log is saved as:

`data/quality_issues/issues_log.csv`

The log records the house, issue type, source row, timestamp, column, original value, injected value, and details.

## Execution

Run the script from the project root:

```bash
python src/data_processing/inject_quality_issues.py
```

## Validation
The script generates corrupted datasets and records the injected issues for later inspection and cleaning.

The generated data is intended for testing the data cleaning pipeline, not for replacing the original processed datasets.