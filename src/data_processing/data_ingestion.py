"""
Data Ingestion Module for Smart Energy Analytics.

Provides utilities for discovering and reading raw sensor files
across target house directories.
"""
from pathlib import Path
from typing import Generator
import pandas as pd


def load_files(
    path: str | Path,
    pattern: str,
    exception: str | None = None,
) -> Generator[tuple[Path, pd.DataFrame]]:
    """
    Search a directory for files matching a pattern and yield (file_path, DataFrame) pairs.

    Parameters
    ----------
    path : str or Path
        Directory path to scan.
    pattern : str
        Glob pattern to match files (e.g. "*.csv").
    exception : str, optional
        Keyword to exclude (e.g. "metadata"). Any file containing this string
        in its filename will be skipped.

    Yields
    ------
    tuple of (Path, pd.DataFrame)
        The path of the matched file and its loaded DataFrame content.
    """
    root_dir = Path(path)
    for file in sorted(root_dir.glob(pattern)):
        if exception and (exception in file.name):
            continue

        yield file, pd.read_csv(file)
