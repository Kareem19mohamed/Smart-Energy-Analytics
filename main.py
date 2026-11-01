from pathlib import Path
import pandas as pd
from src.data_processing import data_ingestion as ingestion, data_transformation as transformation


root_dir = Path("C:/Users/kareem/OneDrive/Desktop/target_houses")
output_folder = Path("data/processed")
output_folder.mkdir(exist_ok=True)


def run_pipeline():
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


if __name__ == "__main__":
    run_pipeline()
