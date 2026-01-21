# Use a slim Python base image
FROM python:3.13.7-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Minimal build tools (helps if wheels aren’t available)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl \
 && rm -rf /var/lib/apt/lists/*

# Install deps first for better layer caching
COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install -r requirements.txt

# Copy the whole project into the image
COPY . /app

EXPOSE 8088

# Start your app with uvicorn
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8088"]
