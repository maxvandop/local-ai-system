FROM python:3.11-slim

WORKDIR /app

# Install TTS dependencies
RUN pip install --no-cache-dir TTS flask

# Expose port
EXPOSE 8005

# Your TTS service code here
CMD ["python", "app.py"]
