FROM python:3.11-slim

WORKDIR /app

# Install whisper dependencies
RUN pip install --no-cache-dir openai-whisper flask

# Expose port
EXPOSE 5001

# Your whisper service code here
CMD ["python", "app.py"]
