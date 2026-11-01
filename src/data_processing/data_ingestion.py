from pathlib import Path
import pandas as pd


def load_files(path: str|Path,pattern: str,exception: list[str]|None=None):
    root_dir=Path(path)
    for file in sorted(root_dir.glob(pattern)):
        if (exception in file.name) and (exception is not None):
            continue

        yield file, pd.read_csv(file)
    
