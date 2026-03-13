FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    libsndfile1 \
    sox \
    && rm -rf /var/lib/apt/lists/*

RUN pip install qwen-tts fastapi uvicorn soundfile numpy torch

COPY app.py .

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8881"]