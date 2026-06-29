FROM apache/superset
USER root
RUN pip install psycopg2-binary --target /app/.venv/lib/python3.10/site-packages --quiet
USER superset
