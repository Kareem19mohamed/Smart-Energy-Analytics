
"""
Data Quality Issues Injection Module for Smart Energy Analytics.

Provides utilities to inject synthetic data quality issues into
smart meter datasets, including additional missing values, outliers,
stuck sensor readings, and duplicate records.

Uses the original processed datasets as input, validates their data
types, and saves the corrupted datasets and an issue log to the
output directory. A fixed random seed makes the injection reproducible.
"""

from pathlib import Path
import random

import pandas as pd


# Project directories. Run this script from the project root.
INPUT_DIR = Path("data/processed")
OUTPUT_DIR = Path("data/quality_issues")
LOG_PATH = OUTPUT_DIR / "issues_log.csv"

RANDOM_SEED = 42
HOUSES = ["House_01", "House_03", "House_04"]

# Deliberately extreme synthetic values used to simulate sensor outliers.
OUTLIERS = {
    "House_01": {"V": 300.0, "P_agg": 15000.0, "ac_1": 6000.0},
    "House_03": {"A": 100.0, "P_agg": 15000.0, "boiler": 8000.0},
    "House_04": {"V": 100.0, "P_agg": 15000.0, "ac_2": 5000.0},
}

# Columns that receive five additional missing values each.
MISSING_COLUMNS = {
    "House_01": ["V", "A"],
    "House_03": ["A", "ac_1"],
    "House_04": ["V", "A"],
}

# One sensor column per house is used to simulate a stuck sensor.
STUCK_COLUMNS = {
    "House_01": "internal_temperature",
    "House_03": "internal_humidity",
    "House_04": "external_temperature",
}

LOG_COLUMNS = [
    "house", "issue_type", "source_row", "timestamp", "column",
    "original_value", "injected_value", "details"
]


def load_typed_dataset(path):
    """Load a dataset and enforce the project's timestamp/numeric dtypes.

    The timestamp column is converted explicitly to datetime64[ns].
    Every other column, including the issues indicator, is converted
    to float64. Invalid values raise a descriptive ValueError.

    Parameters
    ----------
    path : pathlib.Path
        CSV file to load.

    Returns
    -------
    pandas.DataFrame
        Dataset with validated data types.

    Raises
    ------
    ValueError
        If the timestamp is missing/invalid or a non-timestamp column
        contains a value that cannot be converted to a number.
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


def add_log(logs, house, issue_type, row, column="", original="", injected="", details=""):
    """Append one issue record containing the affected row and values."""
    logs.append({
        "house": house,
        "issue_type": issue_type,
        "source_row": row.name,
        "timestamp": row.get("timestamp", ""),
        "column": column,
        "original_value": original,
        "injected_value": injected,
        "details": details,
    })


def inject_for_house(house, rng):
    """Inject the four configured issue types into one house dataset.

    Five new missing values are added to each configured missing-value
    column. One outlier is added to each configured outlier column.
    A six-row stuck-sensor event is created, then two exact duplicate
    records are appended. Every injected change is recorded in the log.

    Parameters
    ----------
    house : str
        House identifier from HOUSES.
    rng : random.Random
        Seeded random number generator shared by the main process.

    Returns
    -------
    tuple
        Issue log entries, original row count, output row count, and
        the path of the saved dataset.

    Raises
    ------
    FileNotFoundError
        If the original dataset does not exist.
    ValueError
        If required columns or suitable rows are unavailable.
    """
    if house not in HOUSES:
        raise ValueError(f"Unsupported house: {house}")

    input_path = INPUT_DIR / f"{house}.csv"
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    df = load_typed_dataset(input_path)
    if "issues" not in df.columns:
        raise ValueError(f"Missing issues column in {input_path}")
    if df["timestamp"].duplicated().any():
        raise ValueError(f"Duplicate timestamps found in original data: {input_path}")

    logs = []

    # 1. Add five new missing values to each configured column.
    for column in MISSING_COLUMNS[house]:
        if column not in df.columns:
            raise ValueError(f"Column '{column}' not found in {input_path}")
        valid_rows = df.index[df[column].notna()].tolist()
        if len(valid_rows) < 5:
            raise ValueError(f"Not enough valid values in {column} for {house}")

        for idx in rng.sample(valid_rows, 5):
            original = df.at[idx, column]
            df.at[idx, column] = float("nan")
            add_log(
                logs, house, "additional_missing_value", df.loc[idx], column,
                original, "NaN",
                "Injected missing value into a previously valid cell."
            )

    # 2. Add one extreme value to each configured outlier column.
    for column, outlier_value in OUTLIERS[house].items():
        if column not in df.columns:
            raise ValueError(f"Column '{column}' not found in {input_path}")
        valid_rows = df.index[df[column].notna()].tolist()
        if not valid_rows:
            raise ValueError(f"No valid values available in {column} for {house}")

        idx = rng.choice(valid_rows)
        original = df.at[idx, column]
        df.at[idx, column] = outlier_value
        add_log(
            logs, house, "outlier", df.loc[idx], column,
            original, outlier_value, "Injected synthetic extreme sensor value."
        )

    # 3. Create a six-row stuck-sensor event. The chosen window must
    # contain changing values and differ from the readings on both sides.
    stuck_column = STUCK_COLUMNS[house]
    if stuck_column not in df.columns:
        raise ValueError(f"Column '{stuck_column}' not found in {input_path}")

    possible_starts = [
        start for start in range(1, len(df) - 6)
        if (
            df[stuck_column].iloc[start:start + 6].notna().all()
            and df[stuck_column].iloc[start:start + 6].nunique() > 1
            and df[stuck_column].iloc[start - 1] != df[stuck_column].iloc[start]
            and df[stuck_column].iloc[start + 6] != df[stuck_column].iloc[start]
        )
    ]
    if not possible_starts:
        raise ValueError(f"Could not find a valid six-row stuck-sensor window in {house}")

    start = rng.choice(possible_starts)
    repeated_value = df.at[start, stuck_column]
    for idx in range(start, start + 6):
        original = df.at[idx, stuck_column]
        df.at[idx, stuck_column] = repeated_value
        if original != repeated_value:
            add_log(
                logs, house, "stuck_sensor", df.loc[idx], stuck_column,
                original, repeated_value,
                f"Changed reading to create a six-row stuck event (start row {start})."
            )

    # 4. Append two exact duplicate records and log their source rows.
    duplicate_sources = rng.sample(list(df.index), 2)
    duplicate_rows = df.loc[duplicate_sources].copy()
    for idx in duplicate_sources:
        add_log(
            logs, house, "duplicate_record", df.loc[idx], "ALL_COLUMNS",
            "original row", "exact duplicate row",
            "Appended exact duplicate record."
        )

    output_df = pd.concat([df, duplicate_rows], ignore_index=True)
    output_df = output_df.sort_values("timestamp", kind="stable").reset_index(drop=True)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / f"{house}_with_issues.csv"
    output_df.to_csv(
        output_path, index=False, date_format="%Y-%m-%d %H:%M:%S"
    )

    return logs, len(df), len(output_df), output_path


def main():
    """Inject issues into all houses and save one combined issue log."""
    rng = random.Random(RANDOM_SEED)
    all_logs = []

    for house in HOUSES:
        logs, input_rows, output_rows, output_path = inject_for_house(house, rng)
        all_logs.extend(logs)
        print(f"\n{house}: {input_rows} original rows -> {output_rows} rows with issues")
        print(f"Injected log entries: {len(logs)}")
        print(f"Saved: {output_path}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(all_logs, columns=LOG_COLUMNS).to_csv(LOG_PATH, index=False)
    print(f"\nIssue log saved: {LOG_PATH}")
    print(f"Total logged injected issues: {len(all_logs)}")


if __name__ == "__main__":
    main()
