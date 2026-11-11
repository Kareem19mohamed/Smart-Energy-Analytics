# Data Cleaning

## Overview

This module cleans smart meter datasets that contain synthetic data quality issues. It uses the original processed datasets as reference data to identify injected sensor errors, remove duplicate records, and handle missing numeric sensor readings.

## Supported Cleaning Operations

1. **Duplicate Records:** Removes exact duplicate rows from the input datasets.
2. **Stuck Sensor Readings:** Detects modified values in the configured stuck sensor columns by comparing them with the original reference data, then replaces affected readings with missing values (`NaN`).
3. **Outliers:** Detects modified values in selected sensor columns by comparing them with the original reference data, then replaces affected values with `NaN`.
4. **Missing Values:** Fills missing numeric sensor readings with the median of each column, excluding the `issues` column.
5. **Data Validation:** Checks required columns, timestamps, duplicate timestamps, row count, column names, and timestamp order.

## Input

The script reads datasets containing injected quality issues from:

`data/quality_issues/`

It also reads the original processed datasets as reference data from:

`data/processed/`

Supported datasets:

- `House_01`
- `House_03`
- `House_04`

Input filenames:

- `House_01_with_issues.csv`
- `House_03_with_issues.csv`
- `House_04_with_issues.csv`

Reference filenames:

- `House_01.csv`
- `House_03.csv`
- `House_04.csv`

## Output

Cleaned datasets are saved in:

`data/cleaned/`

Output filenames:

- `House_01_cleaned.csv`
- `House_03_cleaned.csv`
- `House_04_cleaned.csv`

The script prints a summary for each house, including:

- Number of rows before and after cleaning.
- Number of duplicate rows removed.
- Number of stuck sensor readings detected.
- Number of outliers detected.
- Number of remaining missing numeric sensor values.
- Output file path.

## Execution

Run the script from the project root:

```bash
python src/data_processing/clean_data.py
```

## Validation

The script checks that:

- The required `timestamp` and `issues` columns exist in the input and reference datasets.
- Timestamps are not missing.
- Exact duplicate rows are removed.
- No repeated timestamps remain after duplicate removal.
- Input timestamps exist in the original reference dataset.
- Required original columns are present in the input data.
- The cleaned output has the expected row count and original column structure.
- The timestamp order remains unchanged during cleaning.

If a validation check fails, the script raises an error instead of silently continuing.

## Important Notes

- The original datasets in `data/processed/` are used as reference data and are not overwritten.
- Stuck readings and outliers are identified by comparing configured sensor columns against the original reference data.
- The cleaning process does not use statistical thresholds to identify outliers; it detects changed values in the configured columns.
- Missing numeric sensor readings are filled using each column's median when that median is available.
- Only exact duplicate rows are removed. If repeated timestamps remain afterward, the script raises an error.
- The cleaning process prepares the datasets for further analysis while preserving the expected data structure.