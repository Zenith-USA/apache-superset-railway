FROM apache/superset:latest

USER root

RUN apt-get update && apt-get install -y \
    pkg-config \
    libmariadb-dev \
    default-libmysqlclient-dev \
    libpq-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN pip install mysqlclient psycopg2 && \
    cp -r /usr/local/lib/python3.*/dist-packages/psycopg2* /app/.venv/lib/python3.10/site-packages/ && \
    cp -r /usr/local/lib/python3.*/dist-packages/MySQLdb* /app/.venv/lib/python3.10/site-packages/ && \
    cp -r /usr/local/lib/python3.*/dist-packages/mysqlclient* /app/.venv/lib/python3.10/site-packages/

ENV ADMIN_USERNAME $ADMIN_USERNAME
ENV ADMIN_EMAIL $ADMIN_EMAIL
ENV ADMIN_PASSWORD $ADMIN_PASSWORD
ENV DATABASE $DATABASE

COPY /config/superset_init.sh ./superset_init.sh
RUN chmod +x ./superset_init.sh

COPY /config/superset_config.py /app/
ENV SUPERSET_CONFIG_PATH /app/superset_config.py
ENV SECRET_KEY $SECRET_KEY

USER superset

ENTRYPOINT [ "./superset_init.sh" ]
