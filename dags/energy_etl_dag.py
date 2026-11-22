import os
from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.exceptions import AirflowSkipException
from airflow.operators.python import PythonOperator
from airflow.utils.task_group import TaskGroup

from src.database import load_data

default_args = {
    "retries": 2,
    "retry_delay": timedelta(minutes=1),
}


def ingest_raw():
    """Read the raw monthly files, resample to 15 min, merge with environmental data."""
    raw = Path(os.getenv("RAW_DATA_DIR", "/opt/airflow/raw"))
    houses = [p for p in raw.iterdir() if p.is_dir()] if raw.exists() else []
    if not houses:
        raise AirflowSkipException("No raw data mounted - starting from data/processed")
    from main import run_pipeline
    run_pipeline()


def inject_issues():
    from src.data_processing import inject_quality_issues
    inject_quality_issues.main()


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
    description="Raw smart-meter files -> clean data -> SQL Server",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    default_args=default_args,
    tags=["smart-energy", "etl"],
) as dag:

    with TaskGroup("EXTRACT", prefix_group_id=False):
        t_ingest = PythonOperator(task_id="ingest_raw", python_callable=ingest_raw)

    with TaskGroup("TRANSFORM", prefix_group_id=False):
        t_inject = PythonOperator(
            task_id="inject_quality_issues",
            python_callable=inject_issues,
            trigger_rule="none_failed",  # يكمل حتى لو ingest_raw اتعمله skip
        )
        t_clean = PythonOperator(task_id="clean_data", python_callable=clean)
        t_stage = PythonOperator(task_id="stage_cleaned", python_callable=load_data.extract)
        t_transform = PythonOperator(task_id="transform", python_callable=load_data.transform)

    with TaskGroup("LOAD", prefix_group_id=False):
        t_schema = PythonOperator(task_id="create_schema", python_callable=create_schema)
        t_load = PythonOperator(task_id="load", python_callable=load_data.load)
        t_verify = PythonOperator(task_id="verify", python_callable=load_data.verify)
        t_views = PythonOperator(task_id="create_views", python_callable=create_views)

    (
        t_ingest >> t_inject >> t_clean >> t_stage >> t_transform
        >> t_schema >> t_load >> t_verify >> t_views
    )