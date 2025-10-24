# Backend Dockerfile for Render / generic container deploy
# Uses Python 3.11 to match available binary wheels for Pillow/MediaPipe

FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1

# Install system packages required for Pillow and basic build tools
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential \
       libjpeg-dev \
       zlib1g-dev \
       libpng-dev \
       wget \
       curl \
       ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements and install them (use wheels when available)
COPY requirements.txt ./requirements.txt
RUN pip install --upgrade pip setuptools wheel \
    && pip install -r requirements.txt

# Copy application code
COPY . /app

# Expose default port (Render sets $PORT when running a web service)
EXPOSE 5000

# Start with gunicorn for production-like setup; Render will pass $PORT if configured
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
