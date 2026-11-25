import os
from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.utils.task_group import TaskGroup

from src.database import load_data

HOUSES = ["House_01", "House_03", "House_04"]

default_args = {
    "retries": 2,
    "retry_delay": timedelta(minutes=1),
}


def extract_source():
    """Pull the dirty source files and report what we got. Nothing is changed."""
    root = Path(os.getenv("DATA_ROOT", "/opt/airflow/data")) / "quality_issues"
    for house in HOUSES:
        path = root / f"{house}_with_issues.csv"
        if not path.exists():
            raise FileNotFoundError(f"Source file missing: {path}")
        with open(path, encoding="utf-8") as f:
            rows = sum(1 for _ in f) - 1
        print(f"{house}: {rows:,} rows pulled from the dirty source")


def clean():
    from src.data_processing import clean_data
    clean_data.main()


def create_schema():
    from src.database.run_sql import run_sql_file
    run_sql_file("01_create_database.sql")


def create_views():
    from src.database.run_sql import run_sql_file
    run_sql_file("03_analytical_views.sql")


with DAG(
    dag_id="energy_etl",
    description="Dirty source data -> clean data -> SQL Server",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    default_args=default_args,
    tags=["smart-energy", "etl"],
) as dag:

    with TaskGroup("EXTRACT", prefix_group_id=False):
        t_extract = PythonOperator(task_id="extract_source", python_callable=extract_source)

    with TaskGroup("TRANSFORM", prefix_group_id=False):
        t_clean = PythonOperator(task_id="clean_data", python_callable=clean)
        t_stage = PythonOperator(task_id="stage_cleaned", python_callable=load_data.extract)
        t_transform = PythonOperator(task_id="transform", python_callable=load_data.transform)

    with TaskGroup("LOAD", prefix_group_id=False):
        t_schema = PythonOperator(task_id="create_schema", python_callable=create_schema)
        t_load = PythonOperator(task_id="load", python_callable=load_data.load)
        t_verify = PythonOperator(task_id="verify", python_callable=load_data.verify)
        t_views = PythonOperator(task_id="create_views", python_callable=create_views)

    (
        t_extract >> t_clean >> t_stage >> t_transform
        >> t_schema >> t_load >> t_verify >> t_views
    )