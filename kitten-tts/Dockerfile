FROM python:3.11-slim

WORKDIR /app

# Install TTS dependencies
RUN pip install --no-cache-dir TTS flask

# Copy application code into the container
COPY . .

# Expose port
EXPOSE 8005

# Run the TTS service
CMD ["python", "app.py"]
