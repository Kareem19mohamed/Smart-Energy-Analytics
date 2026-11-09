
import pandas as pd
import random
from pathlib import Path


input_folder = Path("data/processed")
output_folder = Path("data/quality_issues")

random.seed(42)

missing_columns = {
    "House_01": ["V", "A"],
    "House_03": ["A", "ac_1"],
    "House_04": ["V", "A"]
}

outlier_values = {
    "House_01": {"V": 300, "P_agg": 15000, "ac_1": 6000},
    "House_03": {"A": 100, "P_agg": 15000, "boiler": 8000},
    "House_04": {"V": 100, "P_agg": 15000, "ac_2": 5000}
}

stuck_columns = {
    "House_01": "internal_temperature",
    "House_03": "internal_humidity",
    "House_04": "external_temperature"
}

output_folder.mkdir(parents=True, exist_ok=True)

all_logs = []

houses = ["House_01", "House_03", "House_04"]

for house in houses:

    print("\nProcessing", house)

    file_path = input_folder / (house + ".csv")
    df = pd.read_csv(file_path)

    original_columns = df.columns.tolist()

    clean_data = df.copy()

    house_logs = []

    for column in missing_columns[house]:

        valid_rows = df.index[df[column].notna()].tolist()
        selected_rows = random.sample(valid_rows, 5)

        for row in selected_rows:

            old_value = df.at[row, column]
            df.at[row, column] = float("nan")

            house_logs.append({
                "house": house,
                "issue_type": "Artificial Missing Value",
                "row": row,
                "column": column,
                "original_value": old_value,
                "new_value": "NaN"
            })

    for column, value in outlier_values[house].items():

        valid_rows = df.index[df[column].notna()].tolist()
        row = random.choice(valid_rows)

        old_value = df.at[row, column]
        df.at[row, column] = value

        house_logs.append({
            "house": house,
            "issue_type": "Outlier",
            "row": row,
            "column": column,
            "original_value": old_value,
            "new_value": value
        })

    selected_rows = random.sample(
        list(clean_data.index), 2
    )

    duplicate_data = clean_data.loc[selected_rows].copy()

    for row in selected_rows:

        house_logs.append({
            "house": house,
            "issue_type": "Duplicate Record",
            "row": row,
            "column": "All columns",
            "original_value": "Original row",
            "new_value": "Duplicated row"
        })

    column = stuck_columns[house]

    possible_rows = []

    for row in range(len(df) - 5):

        values = df[column].iloc[row:row + 6]

        if values.notna().all():
            possible_rows.append(row)

    if possible_rows:

        start = random.choice(possible_rows)
        repeated_value = df.at[start, column]

        for row in range(start, start + 6):

            old_value = df.at[row, column]
            df.at[row, column] = repeated_value

            house_logs.append({
                "house": house,
                "issue_type": "Stuck Sensor",
                "row": row,
                "column": column,
                "original_value": old_value,
                "new_value": repeated_value
            })

    final_data = pd.concat(
        [df, duplicate_data],
        ignore_index=True
    )

    if final_data.columns.tolist() != original_columns:
        raise ValueError("Original columns have changed!")

    output_path = output_folder / (house + "_with_issues.csv")
    final_data.to_csv(output_path, index=False)

    all_logs.extend(house_logs)

    print("Original rows:", len(clean_data))
    print("Final rows:", len(final_data))

    for issue in [
        "Artificial Missing Value",
        "Outlier",
        "Duplicate Record",
        "Stuck Sensor"
    ]:

        count = sum(
            1 for item in house_logs
            if item["issue_type"] == issue
        )

        print(issue, ":", count)

log_data = pd.DataFrame(all_logs)
log_data.to_csv(output_folder / "issues_log.csv", index=False)

print("\nAll houses processed successfully!")
print("Issue log saved.")

