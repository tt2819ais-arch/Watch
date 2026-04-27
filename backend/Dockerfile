FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv

COPY pyproject.toml ./
RUN pip install --upgrade pip && \
    pip install fastapi "uvicorn[standard]" "sqlalchemy>=2.0" "bcrypt>=4.2" "PyJWT>=2.9" "pydantic>=2.9" "pydantic-settings>=2.5"

COPY app ./app

RUN mkdir -p /data
ENV WATCH_DB_PATH=/data/watch.db

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers"]
