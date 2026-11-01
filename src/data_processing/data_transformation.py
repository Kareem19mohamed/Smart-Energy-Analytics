import pandas as pd 


_VALID_AGG = {"mean", "sum", "max", "min"}


def time_converter(data: pd.DataFrame, duration: str, agg_operation: str = "mean") -> pd.DataFrame:
    if agg_operation not in _VALID_AGG:
        raise ValueError(f"agg_operation must be one of {_VALID_AGG}, got {agg_operation!r}")
    if not isinstance(data.index, pd.DatetimeIndex):
        raise TypeError("DataFrame index must be a DatetimeIndex before resampling.")
    return data.resample(duration).agg(agg_operation)
