
"""
Data Cleaning Module for Smart Energy Analytics.

Provides utilities to detect and clean synthetic data quality issues
in smart meter datasets, including duplicate records, stuck sensor
readings, outliers, and missing numeric sensor values.

Uses the original processed datasets as reference data to identify
modified sensor readings and saves the cleaned datasets to the output
directory.
"""

from pathlib import Path
import pandas as pd
import numpy as np

INPUT_DIR = Path("data/quality_issues")
REFERENCE_DIR = Path("data/processed")
OUTPUT_DIR = Path("data/cleaned")

HOUSES = ["House_01", "House_03", "House_04"]

STUCK_COLUMNS = {
    "House_01": "internal_temperature",
    "House_03": "internal_humidity",
    "House_04": "external_temperature",
}

OUTLIER_COLUMNS = {
    "House_01": ["V", "P_agg", "ac_1"],
    "House_03": ["A", "P_agg", "boiler"],
    "House_04": ["V", "P_agg", "ac_2"],
}


def same_value(left, right):
    """
    Compare two numeric values while treating NaN values as equal.

    Parameters
    ----------
    left : scalar or array-like
        First value or collection of values to compare.
    right : scalar or array-like
        Second value or collection of values to compare.

    Returns
    -------
    bool or numpy.ndarray
        True for values that are approximately equal, including pairs
        of NaN values. The result may be an array for array-like inputs.
    """
    left = pd.to_numeric(left, errors="coerce")
    right = pd.to_numeric(right, errors="coerce")
    return np.isclose(left, right, rtol=1e-9, atol=1e-8, equal_nan=True)


def clean_house(house):
    """
    Clean and validate the dataset for one house.

    Reads the dataset containing injected issues and the corresponding
    original dataset. Removes duplicate records, detects modified stuck
    sensor readings and outliers using the original data as a reference,
    fills missing numeric sensor values with their column medians, and
    saves the cleaned dataset.

    Parameters
    ----------
    house : str
        House identifier. Must be one of the values in HOUSES.

    Returns
    -------
    dict
        Summary containing the house identifier, row counts, number of
        duplicates removed, detected stuck readings, detected outliers,
        remaining missing numeric sensor values, and output file path.

    Raises
    ------
    FileNotFoundError
        If the input or original reference file does not exist.
    ValueError
        If required columns or timestamps are invalid, timestamps are
        duplicated or unmatched, or expected sensor columns are missing.
    AssertionError
        If the saved dataset fails the row count, column, or timestamp
        validation checks.
    """
    input_path = INPUT_DIR / f"{house}_with_issues.csv"
    reference_path = REFERENCE_DIR / f"{house}.csv"

    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")
    if not reference_path.exists():
        raise FileNotFoundError(f"Original reference file not found: {reference_path}")

    df = pd.read_csv(input_path)
    reference = pd.read_csv(reference_path)

    required_columns = {"timestamp", "issues"}
    if not required_columns.issubset(df.columns):
        raise ValueError(f"{input_path} must contain timestamp and issues columns")
    if not required_columns.issubset(reference.columns):
        raise ValueError(f"{reference_path} must contain timestamp and issues columns")

    if df["timestamp"].isna().any() or reference["timestamp"].isna().any():
        raise ValueError(f"Missing timestamps found in {house}")

    input_rows = len(df)
    duplicate_count = int(df.duplicated().sum())
    df = df.drop_duplicates().copy()

    if df["timestamp"].duplicated().any():
        raise ValueError(f"Repeated timestamps remain in {house} after duplicate removal")
    if reference["timestamp"].duplicated().any():
        raise ValueError(f"Original reference has repeated timestamps in {house}")

    if not df["timestamp"].isin(reference["timestamp"]).all():
        raise ValueError(f"Some timestamps in {house} do not exist in the original reference")

    df = df.sort_values("timestamp").reset_index(drop=True)
    reference = reference.set_index("timestamp")
    reference = reference.reindex(df["timestamp"])

    missing_columns = set(reference.columns) - set(df.columns)
    if missing_columns:
        raise ValueError(f"Missing columns in {house}: {sorted(missing_columns)}")

    stuck_column = STUCK_COLUMNS[house]
    if stuck_column not in df.columns:
        raise ValueError(f"Stuck sensor column '{stuck_column}' missing in {house}")

    stuck_original = reference[stuck_column].to_numpy()
    stuck_current = df[stuck_column].to_numpy()
    stuck_mask = ~same_value(stuck_current, stuck_original)
    stuck_count = int(stuck_mask.sum())
    df.loc[stuck_mask, stuck_column] = np.nan

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

    numeric_columns = df.select_dtypes(include="number").columns.tolist()
    sensor_columns = [column for column in numeric_columns if column != "issues"]
    for column in sensor_columns:
        median_value = df[column].median()
        if pd.notna(median_value):
            df[column] = df[column].fillna(median_value)

    remaining_missing = int(df[sensor_columns].isna().sum().sum()) if sensor_columns else 0

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / f"{house}_cleaned.csv"
    df.to_csv(output_path, index=False)

    cleaned = pd.read_csv(output_path)
    if len(cleaned) != len(reference):
        raise AssertionError(f"Cleaned row count does not match reference for {house}")
    if list(cleaned.columns) != list(pd.read_csv(reference_path, nrows=0).columns):
        raise AssertionError(f"Cleaned columns do not match original columns for {house}")
    if cleaned["timestamp"].astype(str).tolist() != df["timestamp"].astype(str).tolist():
        raise AssertionError(f"Timestamp order changed unexpectedly for {house}")

    return {
        "house": house,
        "input_rows": input_rows,
        "cleaned_rows": len(cleaned),
        "duplicates_removed": duplicate_count,
        "stuck_readings_detected": stuck_count,
        "outliers_detected": outlier_count,
        "remaining_numeric_sensor_missing": remaining_missing,
        "output": str(output_path),
    }


def main():
    """
    Clean all configured house datasets and print processing summaries.

    Calls clean_house() for each house in HOUSES and displays the
    number of rows, detected issues, remaining missing numeric values,
    and the location of each saved output file.

    Raises
    ------
    FileNotFoundError
        If a required input or reference dataset is missing.
    ValueError
        If a dataset fails the cleaning validation checks.
    AssertionError
        If a saved cleaned dataset fails output validation.
    """
    results = []
    for house in HOUSES:
        result = clean_house(house)
        results.append(result)
        print(f"\n{house}")
        print(f"Rows before cleaning: {result['input_rows']}")
        print(f"Rows after cleaning: {result['cleaned_rows']}")
        print(f"Duplicates removed: {result['duplicates_removed']}")
        print(f"Stuck readings detected: {result['stuck_readings_detected']}")
        print(f"Outliers detected: {result['outliers_detected']}")
        print(f"Remaining missing numeric sensor values: {result['remaining_numeric_sensor_missing']}")
        print(f"Saved: {result['output']}")

    print("\nAll houses cleaned and validated successfully.")


if __name__ == "__main__":
    main()
