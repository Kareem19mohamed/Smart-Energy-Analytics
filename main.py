"""
Smart Energy Analytics — Pipeline Entry Point.

Orchestrates ingestion, month-by-month temporal resampling,
environmental dataset alignment, quality issue injection,
and data cleaning. Run this file to execute the full pipeline.
"""
from pathlib import Path
import pandas as pd
from src.data_processing import data_ingestion as ingestion, data_transformation as transformation
from src.data_processing import inject_quality_issues, clean_data

root_dir = Path("C:/Users/kareem/OneDrive/Desktop/target_houses")
output_folder = Path("data/processed")
output_folder.mkdir(exist_ok=True)


def run_pipeline() -> None:
    """
    Execute the data ingestion and preprocessing pipeline across all target houses.

    Steps per house:
      1. Discover and load monthly electrical CSV files (excluding metadata).
      2. Resample each monthly electrical file individually to 15-minute intervals
         to preserve monthly data integrity.
      3. Concatenate the resampled monthly electrical frames.
      4. Load and concatenate environmental CSV files.
      5. Join electrical and environmental frames on their DatetimeIndex.
      6. Export the final merged dataset to data/processed/<house_name>.csv.
    """
    for house in sorted(root_dir.iterdir()):
        if not house.is_dir():
            continue

        elec_frames = [
            transformation.time_converter(
                df.set_index(pd.to_datetime(df["timestamp"])).drop(columns=["timestamp"]),
                "15min",
                "mean",
            )
            for _, df in ingestion.load_files(house / "Electric_data", "*.csv", "metadata")
        ]
        if not elec_frames:
            continue
        elec_data = pd.concat(elec_frames)

        env_frames = [
            df for _, df in ingestion.load_files(house / "Environmental_data", "*.csv", "metadata")
        ]
        if not env_frames:
            continue
        env_data = pd.concat(env_frames, ignore_index=True)
        env_data = env_data.set_index(pd.to_datetime(env_data["timestamp"])).drop(columns=["timestamp"])

        house_df = elec_data.join(env_data, how="inner")

        out_path = output_folder / f"{house.name}.csv"
        house_df.to_csv(out_path, index=True)
        print(f"Processing {house.name} completed")


def main() -> None:
    """Run the full Smart Energy Analytics pipeline end to end."""
    run_pipeline()
    inject_quality_issues.main()
    clean_data.main()


if __name__ == "__main__":
    main()
