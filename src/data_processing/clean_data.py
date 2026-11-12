"""
Data Cleaning Module for Smart Energy Analytics.

Cleans the synthetic quality issues injected into the smart meter
house datasets. It removes exact duplicate records, restores modified
stuck-sensor and outlier readings by comparing them with the original
processed datasets, and fills missing numeric sensor values with the
median of each column.

The script validates timestamp and numeric data types before and after
saving. It must be run from the project root directory.
"""

from pathlib import Path

import numpy as np
import pandas as pd


# Project directories.
INPUT_DIR = Path("data/quality_issues")
REFERENCE_DIR = Path("data/processed")
OUTPUT_DIR = Path("data/cleaned")

HOUSES = ["House_01", "House_03", "House_04"]

# Sensor columns modified during the stuck-sensor injection step.
STUCK_COLUMNS = {
    "House_01": "internal_temperature",
    "House_03": "internal_humidity",
    "House_04": "external_temperature",
}

# Sensor columns modified during the outlier injection step.
OUTLIER_COLUMNS = {
    "House_01": ["V", "P_agg", "ac_1"],
    "House_03": ["A", "P_agg", "boiler"],
    "House_04": ["V", "P_agg", "ac_2"],
}


def load_typed_dataset(path):
    """Load a CSV and enforce datetime64[ns] and float64 data types.

    Parameters
    ----------
    path : pathlib.Path
        CSV file to load.

    Returns
    -------
    pandas.DataFrame
        Dataset with timestamp stored as datetime64[ns] and every
        remaining column stored as float64.

    Raises
    ------
    ValueError
        If timestamp values or numeric values cannot be converted.
    """
    df = pd.read_csv(path)

    if "timestamp" not in df.columns:
        raise ValueError(f"Missing timestamp column in {path}")

    try:
        df["timestamp"] = pd.to_datetime(
            df["timestamp"], errors="raise"
        ).astype("datetime64[ns]")
    except (TypeError, ValueError, OverflowError) as error:
        raise ValueError(f"Invalid timestamp values in {path}: {error}") from error

    if df["timestamp"].isna().any():
        raise ValueError(f"Missing timestamp values found in {path}")

    numeric_columns = [column for column in df.columns if column != "timestamp"]
    for column in numeric_columns:
        try:
            df[column] = pd.to_numeric(
                df[column], errors="raise"
            ).astype("float64")
        except (TypeError, ValueError) as error:
            raise ValueError(
                f"Column '{column}' in {path} contains non-numeric values"
            ) from error

    return df


def same_value(left, right):
    """Compare numeric values while treating NaN as equal to NaN."""
    left = pd.to_numeric(left, errors="coerce")
    right = pd.to_numeric(right, errors="coerce")
    return np.isclose(
        left, right, rtol=1e-9, atol=1e-8, equal_nan=True
    )


def clean_house(house):
    """Clean one house dataset and validate the saved output.

    The original processed dataset is the reference for identifying
    the intentionally injected stuck-sensor and outlier changes.
    Missing numeric sensor values are imputed using column medians.

    Parameters
    ----------
    house : str
        House identifier from HOUSES.

    Returns
    -------
    dict
        Summary of row counts, detected issues, data types, and output path.

    Raises
    ------
    FileNotFoundError
        If the corrupted input or original reference file is missing.
    ValueError
        If required columns, timestamps, or schema checks fail.
    AssertionError
        If saved output validation fails or missing sensor values remain.
    """
    if house not in HOUSES:
        raise ValueError(f"Unsupported house: {house}")

    input_path = INPUT_DIR / f"{house}_with_issues.csv"
    reference_path = REFERENCE_DIR / f"{house}.csv"

    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")
    if not reference_path.exists():
        raise FileNotFoundError(f"Original reference file not found: {reference_path}")

    # Load both datasets using the same explicit data type rules.
    df = load_typed_dataset(input_path)
    reference = load_typed_dataset(reference_path)

    required_columns = {"timestamp", "issues"}
    if not required_columns.issubset(df.columns):
        raise ValueError(f"{input_path} must contain timestamp and issues columns")
    if not required_columns.issubset(reference.columns):
        raise ValueError(f"{reference_path} must contain timestamp and issues columns")

    # The original reference must have one row per timestamp.
    if reference["timestamp"].duplicated().any():
        raise ValueError(f"Original reference has repeated timestamps in {house}")

    # Both datasets must have exactly the same schema and column order.
    if list(df.columns) != list(reference.columns):
        raise ValueError(f"Column names or order differ from the original in {house}")

    original_columns = list(reference.columns)

    # Remove exact duplicate rows introduced by the injection script.
    input_rows = len(df)
    duplicate_count = int(df.duplicated().sum())
    df = df.drop_duplicates().copy()

    # Each timestamp must identify one row after exact duplicate removal.
    if df["timestamp"].duplicated().any():
        raise ValueError(f"Repeated timestamps remain in {house} after duplicate removal")

    # Do not allow rows that are absent from the original reference.
    if not df["timestamp"].isin(reference["timestamp"]).all():
        raise ValueError(f"Some timestamps in {house} do not exist in the original reference")

    # Sort the corrupted data, then align the reference to the same timestamps.
    df = df.sort_values("timestamp").reset_index(drop=True)
    reference = reference.set_index("timestamp")
    reference = reference.reindex(df["timestamp"])

    # Detect stuck-sensor changes by comparing the configured column
    # against the original reference, then mark changed cells as missing.
    stuck_column = STUCK_COLUMNS[house]
    if stuck_column not in df.columns:
        raise ValueError(f"Stuck sensor column '{stuck_column}' missing in {house}")

    stuck_original = reference[stuck_column].to_numpy()
    stuck_current = df[stuck_column].to_numpy()
    stuck_mask = ~same_value(stuck_current, stuck_original)
    stuck_count = int(stuck_mask.sum())
    df.loc[stuck_mask, stuck_column] = np.nan

    # Detect outliers only in the configured columns. Missing values are
    # excluded here because they are handled by the imputation step below.
    outlier_count = 0
    for column in OUTLIER_COLUMNS[house]:
        if column not in df.columns:
            raise ValueError(f"Outlier column '{column}' missing in {house}")

        original_values = reference[column].to_numpy()
        current_values = df[column].to_numpy()
        outlier_mask = (
            pd.notna(current_values)
            & pd.notna(original_values)
            & ~same_value(current_values, original_values)
        )
        outlier_count += int(outlier_mask.sum())
        df.loc[outlier_mask, column] = np.nan

    # Fill missing numeric sensor values using each column's median.
    # The issues indicator is not a sensor measurement and is excluded.
    numeric_columns = df.select_dtypes(include="number").columns.tolist()
    sensor_columns = [column for column in numeric_columns if column != "issues"]

    for column in sensor_columns:
        median_value = df[column].median()
        if pd.notna(median_value):
            df[column] = df[column].fillna(median_value)

    remaining_missing = (
        int(df[sensor_columns].isna().sum().sum()) if sensor_columns else 0
    )
    if remaining_missing != 0:
        raise AssertionError(
            f"Missing numeric sensor values remain in {house}: {remaining_missing}"
        )

    # Save the cleaned dataset.
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / f"{house}_cleaned.csv"
    df.to_csv(output_path, index=False, date_format="%Y-%m-%d %H:%M:%S")

    # Reload the actual saved CSV and validate its schema and data types.
    cleaned = load_typed_dataset(output_path)

    if len(cleaned) != len(reference):
        raise AssertionError(f"Cleaned row count does not match reference for {house}")
    if list(cleaned.columns) != original_columns:
        raise AssertionError(f"Cleaned columns do not match original columns for {house}")
    if not cleaned["timestamp"].is_monotonic_increasing:
        raise AssertionError(f"Timestamps are not sorted in {house}")
    if cleaned["timestamp"].duplicated().any():
        raise AssertionError(f"Duplicate timestamps remain in cleaned data for {house}")
    if not cleaned["timestamp"].equals(df["timestamp"].reset_index(drop=True)):
        raise AssertionError(f"Timestamp order changed unexpectedly for {house}")
    if cleaned["timestamp"].tolist() != reference.index.tolist():
        raise AssertionError(f"Cleaned timestamps do not match original reference for {house}")
    if str(cleaned["timestamp"].dtype) != "datetime64[ns]":
        raise AssertionError(f"Timestamp dtype must be datetime64[ns] in {house}")

    for column in cleaned.columns:
        if column != "timestamp" and cleaned[column].dtype != "float64":
            raise AssertionError(
                f"Column '{column}' must have float64 dtype in {house}, "
                f"got {cleaned[column].dtype}"
            )

    saved_missing = (
        int(cleaned[sensor_columns].isna().sum().sum()) if sensor_columns else 0
    )
    if saved_missing != 0:
        raise AssertionError(
            f"Missing numeric sensor values remain in saved output for {house}: "
            f"{saved_missing}"
        )

    return {
        "house": house,
        "input_rows": input_rows,
        "cleaned_rows": len(cleaned),
        "duplicates_removed": duplicate_count,
        "stuck_readings_detected": stuck_count,
        "outliers_detected": outlier_count,
        "remaining_numeric_sensor_missing": saved_missing,
        "timestamp_dtype": str(cleaned["timestamp"].dtype),
        "numeric_dtype": "float64",
        "output": str(output_path),
    }


def main():
    """Clean all configured house datasets and print validation results."""
    for house in HOUSES:
        result = clean_house(house)
        print(f"\n{house}")
        print(f"Rows before cleaning: {result['input_rows']}")
        print(f"Rows after cleaning: {result['cleaned_rows']}")
        print(f"Duplicates removed: {result['duplicates_removed']}")
        print(f"Stuck readings detected: {result['stuck_readings_detected']}")
        print(f"Outliers detected: {result['outliers_detected']}")
        print(
            "Remaining missing numeric sensor values: "
            f"{result['remaining_numeric_sensor_missing']}"
        )
        print(f"Timestamp dtype: {result['timestamp_dtype']}")
        print(f"Numeric dtype: {result['numeric_dtype']}")
        print(f"Saved: {result['output']}")

    print("\nAll houses cleaned and validated successfully.")



