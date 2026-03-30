FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY services/auth_api/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

COPY services /app/services
COPY main.py /app/main.py
COPY auth_service.py /app/auth_service.py

EXPOSE 8001

CMD ["uvicorn", "services.auth_api.app:app", "--host", "0.0.0.0", "--port", "8001"]

