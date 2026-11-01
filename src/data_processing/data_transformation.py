"""
Data Transformation Module for Smart Energy Analytics.

Provides time-series aggregation and frequency resampling utilities.
"""
import pandas as pd

_VALID_AGG = {"mean", "sum", "max", "min"}


def time_converter(
    data: pd.DataFrame,
    duration: str,
    agg_operation: str = "mean",
) -> pd.DataFrame:
    """
    Resample a time-indexed DataFrame to a target frequency using an aggregation operation.

    Parameters
    ----------
    data : pd.DataFrame
        Input DataFrame. Must have a pd.DatetimeIndex.
    duration : str
        Pandas frequency offset alias (e.g., '15min', '1h', '1D').
    agg_operation : {'mean', 'sum', 'max', 'min'}, default 'mean'
        Aggregation function to apply across each resampled window.

    Returns
    -------
    pd.DataFrame
        Resampled and aggregated DataFrame.

    Raises
    ------
    ValueError
        If agg_operation is not one of {'mean', 'sum', 'max', 'min'}.
    TypeError
        If data does not have a pd.DatetimeIndex.
    """
    if agg_operation not in _VALID_AGG:
        raise ValueError(f"agg_operation must be one of {_VALID_AGG}, got {agg_operation!r}")
    if not isinstance(data.index, pd.DatetimeIndex):
        raise TypeError("DataFrame index must be a DatetimeIndex before resampling.")
    return data.resample(duration).agg(agg_operation)
