# Use an official Python runtime as a parent image
FROM python:3.10-slim

# Install ffmpeg (required for whisper) and git (required for pip install from git)
RUN apt-get update && \
    apt-get install -y ffmpeg git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Install whisper (and torch, which is a dependency)
RUN pip install --upgrade pip
RUN pip install git+https://github.com/openai/whisper.git

# Clean any previous (possibly corrupted) model cache
RUN rm -rf /root/.cache/whisper

# Pre-download the 'small' model to avoid runtime download/corruption
RUN whisper --model small --help || true

# (Optional) Expose a port if you plan to run an API server
EXPOSE 5001

# Default command: run whisper CLI (change as needed)
COPY api_server.py /app/api_server.py
ENTRYPOINT ["python", "api_server.py"]
