
from pathlib import Path
import random

"""
Data Quality Issues Injection Module for Smart Energy Analytics.

Provides utilities to introduce synthetic data quality issues into
processed smart meter datasets for testing the data cleaning pipeline.

Supported issues include additional missing values, extreme sensor
outliers, stuck sensor readings, and duplicate records. An issue log
is generated to record the injected changes.
"""

from pathlib import Path
import random
import pandas as pd

INPUT_DIR = Path("data/processed")
OUTPUT_DIR = Path("data/quality_issues")
LOG_PATH = OUTPUT_DIR / "issues_log.csv"

RANDOM_SEED = 42
HOUSES = ["House_01", "House_03", "House_04"]

OUTLIERS = {
    "House_01": {"V": 300.0, "P_agg": 15000.0, "ac_1": 6000.0},
    "House_03": {"A": 100.0, "P_agg": 15000.0, "boiler": 8000.0},
    "House_04": {"V": 100.0, "P_agg": 15000.0, "ac_2": 5000.0},
}

MISSING_COLUMNS = {
    "House_01": ["V", "A"],
    "House_03": ["A", "ac_1"],
    "House_04": ["V", "A"],
}

STUCK_COLUMNS = {
    "House_01": "internal_temperature",
    "House_03": "internal_humidity",
    "House_04": "external_temperature",
}

LOG_COLUMNS = [
    "house", "issue_type", "source_row", "timestamp", "column",
    "original_value", "injected_value", "details"
]


def add_log(logs, house, issue_type, row, column="", original="", injected="", details=""):
    """
    Add a record describing an injected data quality issue.

    Parameters
    ----------
    logs : list
        List that stores issue log records.
    house : str
        Identifier of the house dataset being processed.
    issue_type : str
        Type of issue injected into the dataset.
    row : pandas.Series
        Original row containing the timestamp and row index information.
    column : str, default ''
        Name of the affected column, or ALL_COLUMNS for duplicate records.
    original : object, default ''
        Original value before the issue was injected.
    injected : object, default ''
        Value or description of the injected change.
    details : str, default ''
        Additional explanation of the injected issue.

    Returns
    -------
    None
        Appends a log record to the provided logs list.
    """
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
    """
    Inject synthetic data quality issues into one house dataset.

    Reads the original processed dataset, introduces missing values,
    outliers, a six-row stuck sensor event, and duplicate records.
    Saves the modified dataset and returns its issue log information.

    Parameters
    ----------
    house : str
        House identifier. Must be one of the values in HOUSES.
    rng : random.Random
        Random number generator used to select rows reproducibly.

    Returns
    -------
    tuple
        A tuple containing:
        - logs: list of records describing injected issues.
        - input_rows: number of original rows.
        - output_rows: number of rows after adding duplicates.
        - output_path: path to the saved dataset.

    Raises
    ------
    FileNotFoundError
        If the original processed dataset does not exist.
    ValueError
        If required columns or target sensor columns are missing,
        there are insufficient valid values, or a valid stuck-sensor
        window cannot be found.
    """
    input_path = INPUT_DIR / f"{house}.csv"
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    df = pd.read_csv(input_path)
    required = {"timestamp", "issues"}
    missing_required = required - set(df.columns)
    if missing_required:
        raise ValueError(f"{input_path} is missing columns: {sorted(missing_required)}")

    logs = []

    for column in MISSING_COLUMNS[house]:
        if column not in df.columns:
            raise ValueError(f"Column '{column}' not found in {input_path}")
        valid_rows = df.index[df[column].notna()].tolist()
        if len(valid_rows) < 5:
            raise ValueError(f"Not enough valid values in {column} for {house}")
        for idx in rng.sample(valid_rows, 5):
            original = df.at[idx, column]
            df.at[idx, column] = float("nan")
            add_log(logs, house, "additional_missing_value", df.loc[idx], column,
                    original, "NaN", "Injected missing value into a previously valid cell.")

    for column, outlier_value in OUTLIERS[house].items():
        if column not in df.columns:
            raise ValueError(f"Column '{column}' not found in {input_path}")
        valid_rows = df.index[df[column].notna()].tolist()
        if not valid_rows:
            raise ValueError(f"No valid values available in {column} for {house}")
        idx = rng.choice(valid_rows)
        original = df.at[idx, column]
        df.at[idx, column] = outlier_value
        add_log(logs, house, "outlier", df.loc[idx], column,
                original, outlier_value, "Injected synthetic extreme sensor value.")

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
        if pd.notna(original) and original != repeated_value:
            add_log(logs, house, "stuck_sensor", df.loc[idx], stuck_column,
                    original, repeated_value,
                    f"Changed reading to create a six-row stuck event (start row {start}).")

    duplicate_sources = rng.sample(list(df.index), 2)
    duplicate_rows = df.loc[duplicate_sources].copy()
    for idx in duplicate_sources:
        add_log(logs, house, "duplicate_record", df.loc[idx], "ALL_COLUMNS",
                "original row", "exact duplicate row", "Appended exact duplicate record.")

    output_df = pd.concat([df, duplicate_rows], ignore_index=True)
    output_df = output_df.sort_values("timestamp", kind="stable").reset_index(drop=True)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / f"{house}_with_issues.csv"
    output_df.to_csv(output_path, index=False)

    return logs, len(df), len(output_df), output_path


def main():
    """
    Inject data quality issues into all configured house datasets.

    Initializes a reproducible random number generator, processes each
    house, prints a summary of the injected issues, and saves a combined
    CSV log containing all recorded changes.

    Raises
    ------
    FileNotFoundError
        If a required original processed dataset does not exist.
    ValueError
        If a dataset cannot be processed due to missing columns or
        unsuitable sensor values.
    """
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



