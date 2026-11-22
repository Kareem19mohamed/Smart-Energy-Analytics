import os
import re

from src.database.load_data import get_engine

SQL_DIR = os.path.dirname(os.path.abspath(__file__))


def split_batches(sql: str) -> list[str]:
    """Split a SQL Server script into batches at lines that contain only GO."""
    batches, current = [], []
    for line in sql.splitlines():
        if re.fullmatch(r"\s*GO\s*;?\s*", line, flags=re.IGNORECASE):
            batches.append("\n".join(current))
            current = []
        else:
            current.append(line)
    batches.append("\n".join(current))
    return [b for b in batches if b.strip()]


def read_sql(path: str) -> str:
    try:
        with open(path, encoding="utf-8-sig") as f:
            return f.read()
    except UnicodeDecodeError:
        with open(path, encoding="utf-16") as f:
            return f.read()


def run_sql_file(filename: str) -> None:
    """Run a .sql file from src/database, batch by batch."""
    batches = split_batches(read_sql(os.path.join(SQL_DIR, filename)))
    engine = get_engine()
    with engine.connect().execution_options(isolation_level="AUTOCOMMIT") as conn:
        for number, batch in enumerate(batches, start=1):
            conn.exec_driver_sql(batch)
            print(f"{filename}: batch {number}/{len(batches)} done")
    print(f"{filename}: finished")