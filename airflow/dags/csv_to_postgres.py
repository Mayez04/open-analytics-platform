from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import boto3
import pandas as pd
from sqlalchemy import create_engine
import io

from lib.platform_config import get_platform_config

_cfg = get_platform_config()
MINIO_ENDPOINT   = _cfg["minio_endpoint"]
MINIO_ACCESS_KEY = _cfg["minio_access_key"]
MINIO_SECRET_KEY = _cfg["minio_secret_key"]
BUCKET_NAME      = _cfg["minio_bucket"]
PG_CONN          = _cfg["pg_conn"]

FILE_NAME        = "life_expectancy.csv"

def load_csv_to_postgres():
    # 1. Pull CSV from MinIO
    s3 = boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        aws_access_key_id=MINIO_ACCESS_KEY,
        aws_secret_access_key=MINIO_SECRET_KEY,
    )
    obj = s3.get_object(Bucket=BUCKET_NAME, Key=FILE_NAME)
    df = pd.read_csv(io.BytesIO(obj["Body"].read()))

    print(f"Loaded {len(df)} rows, columns: {list(df.columns)}")

    # 2. Push to Postgres
    engine = create_engine(PG_CONN)
    df.to_sql(
        name="raw_data",        # table name in Postgres
        con=engine,
        schema="public",
        if_exists="replace",    # replace table on each run
        index=False,
    )
    print("Done — data loaded into postgres public.raw_data")

with DAG(
    dag_id="csv_minio_to_postgres",
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,    # manual trigger only
    catchup=False,
) as dag:
    load = PythonOperator(
        task_id="load_csv_to_postgres",
        python_callable=load_csv_to_postgres,
    )
