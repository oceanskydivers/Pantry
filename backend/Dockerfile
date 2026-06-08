FROM python:3.12-slim

# Install ffmpeg and yt-dlp system dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy app
COPY main.py .

# Cloud Run expects the app to listen on $PORT (default 8080)
ENV PORT=8080
EXPOSE 8080

CMD ["python", "main.py"]
